package oxtelegram

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// progressiveSource simulates Telegram progressive download: only ranges that were
// EnsureAvailable'd are considered available; fills happen on demand.
type progressiveSource struct {
	memSource
	mu     sync.Mutex
	have   []byteRange
	delays atomic.Int32
}

func newProgressiveSource(t *testing.T, size int64) *progressiveSource {
	t.Helper()
	return &progressiveSource{memSource: *newMemSource(t, size)}
}

func (p *progressiveSource) AvailableFrom() int64 {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.have) == 0 {
		return 0
	}
	return p.have[0].start
}

func (p *progressiveSource) AvailableUpTo() int64 {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.have) == 0 {
		return 0
	}
	max := p.have[0].end
	for _, r := range p.have[1:] {
		if r.end > max {
			max = r.end
		}
	}
	return max
}

func (p *progressiveSource) IsComplete() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.have) == 1 && p.have[0].start == 0 && p.have[0].end >= p.size
}

func (p *progressiveSource) EnsureAvailable(_ context.Context, offset, length int64) error {
	p.delays.Add(1)
	time.Sleep(5 * time.Millisecond)
	needEnd := offset + length
	if needEnd > p.size {
		needEnd = p.size
	}
	p.mu.Lock()
	p.have = mergeSmokeRanges(p.have, byteRange{start: offset, end: needEnd})
	p.mu.Unlock()
	return nil
}

func mergeSmokeRanges(in []byteRange, n byteRange) []byteRange {
	out := make([]byteRange, 0, len(in)+1)
	merged := false
	for _, r := range in {
		if r.end < n.start || r.start > n.end {
			if !merged && n.end < r.start {
				out = append(out, n)
				merged = true
			}
			out = append(out, r)
			continue
		}
		if r.start < n.start {
			n.start = r.start
		}
		if r.end > n.end {
			n.end = r.end
		}
	}
	if !merged {
		out = append(out, n)
	}
	return out
}

func getRange(t *testing.T, url, rangeHdr string) (status int, n int64) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	if rangeHdr != "" {
		req.Header.Set("Range", rangeHdr)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, int64(len(body))
}

// Smoke: play start → jump ~70% → +30s-ish → jump back (seek matrix).
func TestSmoke_SeekJumpMatrix(t *testing.T) {
	const size = 100 * 1024 * 1024
	src := newProgressiveSource(t, size)
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(1, src)
	url, err := srv.URLFor(1)
	if err != nil {
		t.Fatal(err)
	}

	st, n := getRange(t, url, "bytes=0-")
	if st != http.StatusPartialContent && st != http.StatusOK {
		t.Fatalf("start play status=%d", st)
	}
	if n <= 0 {
		t.Fatal("start play empty body")
	}

	at70 := size * 70 / 100
	st, n = getRange(t, url, fmt.Sprintf("bytes=%d-", at70))
	if st != http.StatusPartialContent {
		t.Fatalf("70%% seek status=%d", st)
	}
	if n <= 0 {
		t.Fatal("70% seek empty")
	}

	at70plus := at70 + 30*1024*1024
	if at70plus >= size {
		at70plus = size - 1024
	}
	st, n = getRange(t, url, fmt.Sprintf("bytes=%d-", at70plus))
	if st != http.StatusPartialContent {
		t.Fatalf("+30s seek status=%d", st)
	}
	if n <= 0 {
		t.Fatal("+30s seek empty")
	}

	st, n = getRange(t, url, "bytes=0-")
	if st != http.StatusPartialContent && st != http.StatusOK {
		t.Fatalf("jump-back status=%d", st)
	}
	if n <= 0 {
		t.Fatal("jump-back empty")
	}
}

// Smoke: concurrent mid + EOF cue ranges (seek-stall class).
func TestSmoke_ConcurrentRanges(t *testing.T) {
	const size = 80 * 1024 * 1024
	src := newProgressiveSource(t, size)
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(2, src)
	url, err := srv.URLFor(2)
	if err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	errs := make(chan string, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		st, n := getRange(t, url, fmt.Sprintf("bytes=%d-", size-2*1024*1024))
		if st != http.StatusPartialContent || n <= 0 {
			errs <- fmt.Sprintf("eof cue status=%d n=%d", st, n)
		}
	}()
	go func() {
		defer wg.Done()
		st, n := getRange(t, url, fmt.Sprintf("bytes=%d-", size/2))
		if st != http.StatusPartialContent || n <= 0 {
			errs <- fmt.Sprintf("mid seek status=%d n=%d", st, n)
		}
	}()
	wg.Wait()
	close(errs)
	for msg := range errs {
		t.Fatal(msg)
	}
}

func TestSmoke_SessionURIStopMatching(t *testing.T) {
	if !SessionURIRefersToFile("http://127.0.0.1:50166/3", 3) {
		t.Fatal("expected match for /3")
	}
	if SessionURIRefersToFile("http://127.0.0.1:50166/2", 3) {
		t.Fatal("stale /2 must not match active 3")
	}
	if SessionURIRefersToFile("", 3) {
		t.Fatal("empty uri")
	}
}

func TestSmoke_EpisodeSwitchStopIgnoresStaleURI(t *testing.T) {
	oldURI := "http://127.0.0.1:61412/2"
	newID := 3
	if SessionURIRefersToFile(oldURI, newID) {
		t.Fatal("episode switch: stopping old URI must not match new file id")
	}
}
