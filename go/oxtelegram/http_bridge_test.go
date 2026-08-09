package oxtelegram

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// memSource is a fully-available file ByteSource for HTTP bridge unit tests.
type memSource struct {
	path     string
	size     int64
	cancels  atomic.Int32
	ensureMu sync.Mutex
}

func newMemSource(t *testing.T, size int64) *memSource {
	t.Helper()
	path := filepath.Join(t.TempDir(), "blob")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	chunk := make([]byte, 64*1024)
	for i := range chunk {
		chunk[i] = byte(i)
	}
	var written int64
	for written < size {
		n := int64(len(chunk))
		if written+n > size {
			n = size - written
		}
		if _, err := f.Write(chunk[:n]); err != nil {
			t.Fatal(err)
		}
		written += n
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	return &memSource{path: path, size: size}
}

func (m *memSource) Size() int64                                  { return m.size }
func (m *memSource) LocalPath() string                            { return m.path }
func (m *memSource) AvailableFrom() int64                         { return 0 }
func (m *memSource) AvailableUpTo() int64                         { return m.size }
func (m *memSource) IsComplete() bool                             { return true }
func (m *memSource) EnsureAvailable(context.Context, int64, int64) error { return nil }
func (m *memSource) CancelCurrentRead()                           { m.cancels.Add(1) }

func TestHttpBridge_openEndedRangeCapped(t *testing.T) {
	const size = 50 * 1024 * 1024
	src := newMemSource(t, size)
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(7, src)
	url, err := srv.URLFor(7)
	if err != nil {
		t.Fatal(err)
	}

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Range", "bytes=1000000-")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("status=%d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(body)) != httpBridgeOpenRange {
		t.Fatalf("open-ended body len=%d want=%d", len(body), httpBridgeOpenRange)
	}
	cr := resp.Header.Get("Content-Range")
	wantCR := fmt.Sprintf("bytes %d-%d/%d", 1_000_000, 1_000_000+httpBridgeOpenRange-1, size)
	if cr != wantCR {
		t.Fatalf("Content-Range=%q want %q", cr, wantCR)
	}
}

func TestHttpBridge_explicitRange(t *testing.T) {
	src := newMemSource(t, 10_000_000)
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(1, src)
	url, err := srv.URLFor(1)
	if err != nil {
		t.Fatal(err)
	}

	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Range", "bytes=100-199")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if len(body) != 100 {
		t.Fatalf("len=%d", len(body))
	}
}

func TestHttpBridge_cancelAfterLastStream(t *testing.T) {
	src := newMemSource(t, 2*1024*1024)
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(3, src)
	url, err := srv.URLFor(3)
	if err != nil {
		t.Fatal(err)
	}

	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Range", "bytes=0-1023")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()

	deadline := time.Now().Add(2 * time.Second)
	for src.cancels.Load() < 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if src.cancels.Load() < 1 {
		t.Fatalf("expected cancel after last stream, got %d", src.cancels.Load())
	}
}

func TestHttpBridge_concurrentRangesNoEarlyCancel(t *testing.T) {
	src := newMemSource(t, 8*1024*1024)
	counting := &countingCancelSource{memSource: *src}
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(3, counting)
	url, err := srv.URLFor(3)
	if err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			start := int64(i) * 256 * 1024
			req, _ := http.NewRequest(http.MethodGet, url, nil)
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, start+4095))
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Errorf("req %d: %v", i, err)
				return
			}
			_, _ = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}(i)
	}
	wg.Wait()
	// After all concurrent ranges finish, cancel should have fired at least once (last leave).
	deadline := time.Now().Add(2 * time.Second)
	for counting.cancels.Load() < 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if counting.cancels.Load() < 1 {
		t.Fatal("expected cancel after concurrent ranges drained")
	}
}

type countingCancelSource struct {
	memSource
}

func TestHttpBridge_seekHandoffDoesNotCancelNewProbe(t *testing.T) {
	// Reproduces mpv seek: old conn ends (active→0) while new conn is in EnsureAvailable.
	const size = 40 * 1024 * 1024
	src := &slowProbeSource{memSource: *newMemSource(t, size), probeDelay: 200 * time.Millisecond}
	srv := NewHttpBridgeServer()
	t.Cleanup(func() { _ = srv.Close() })
	srv.Register(9, src)
	url, err := srv.URLFor(9)
	if err != nil {
		t.Fatal(err)
	}

	done1 := make(chan error, 1)
	go func() {
		req, _ := http.NewRequest(http.MethodGet, url, nil)
		req.Header.Set("Range", "bytes=0-1023")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			done1 <- err
			return
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		done1 <- nil
	}()

	time.Sleep(30 * time.Millisecond)

	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-", size/2))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("seek status=%d (cancel race returned error?)", resp.StatusCode)
	}
	n, _ := io.Copy(io.Discard, resp.Body)
	if n <= 0 {
		t.Fatal("seek body empty")
	}
	<-done1
}

type slowProbeSource struct {
	memSource
	probeDelay time.Duration
	probes     atomic.Int32
}

func (s *slowProbeSource) EnsureAvailable(ctx context.Context, offset, length int64) error {
	s.probes.Add(1)
	select {
	case <-time.After(s.probeDelay):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func TestParseRangeHelpers(t *testing.T) {
	if parseRangeStart("bytes=42-") != 42 {
		t.Fatal("start")
	}
	end, ok := parseRangeEnd("bytes=10-20", 100)
	if !ok || end != 20 {
		t.Fatalf("end=%d ok=%v", end, ok)
	}
	_, ok = parseRangeEnd("bytes=10-", 100)
	if ok {
		t.Fatal("open-ended should have no end")
	}
}
