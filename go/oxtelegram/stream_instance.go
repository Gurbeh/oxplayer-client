package oxtelegram

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"
)

// streamEnsureAvailableTimeout bounds one blocking Read wait — matches
// httpBridgeEnsureAvailableTimeout so a stalled MTProto fetch surfaces as a read error instead of
// hanging mpv's demuxer thread forever.
const streamEnsureAvailableTimeout = 2 * time.Minute

// StreamInstance adapts a ByteSource to the sequential, position-based read/seek/size/cancel
// shape mpv's stream_cb API expects (stream/stream_cb.h upstream: read_fn takes no offset, the
// stream tracks its own cursor, seek_fn repositions it). Platform cgo glue
// (cshared/main.go, a future cshared_android/main.go) wraps this with thin C-ABI trampolines;
// all the actual blocking/positioning/cancellation logic lives here once, not duplicated per
// platform — same "reuse, don't rebuild" principle as DownloadByteSource for the HTTP bridge.
//
// One StreamInstance corresponds to one mpv_stream_cb_info lifetime (one open_fn/close_fn pair),
// not to the underlying playback session — a track/subtitle switch that makes mpv reopen the URI
// creates a new StreamInstance over the *same* ByteSource/DownloadSession, mirroring how the HTTP
// bridge already treats each Range connection as independent of the download session's lifetime.
type StreamInstance struct {
	src  ByteSource
	file *os.File

	mu     sync.Mutex
	pos    int64
	cancel context.CancelFunc
}

func NewStreamInstance(src ByteSource) (*StreamInstance, error) {
	f, err := os.Open(src.LocalPath())
	if err != nil {
		return nil, fmt.Errorf("stream instance: open cache file: %w", err)
	}
	return &StreamInstance{src: src, file: f}, nil
}

// Read fills buf starting at the instance's current position, blocking until enough bytes are
// downloaded (or Cancel or the timeout interrupts it), then advances the position — matches
// mpv_stream_cb_read_fn's read(2)-like contract (short reads allowed, 0 = EOF).
func (s *StreamInstance) Read(buf []byte) (int, error) {
	s.mu.Lock()
	pos := s.pos
	size := s.src.Size()
	if pos >= size {
		s.mu.Unlock()
		return 0, nil
	}
	want := int64(len(buf))
	if pos+want > size {
		want = size - pos
	}
	ctx, cancel := context.WithTimeout(context.Background(), streamEnsureAvailableTimeout)
	s.cancel = cancel
	s.mu.Unlock()
	defer cancel()

	if err := s.src.EnsureAvailable(ctx, pos, want); err != nil {
		return 0, err
	}

	n, err := s.file.ReadAt(buf[:want], pos)
	if err != nil && n == 0 {
		return 0, err
	}
	s.mu.Lock()
	s.pos = pos + int64(n)
	s.mu.Unlock()
	return n, nil
}

// Seek repositions without blocking on a download — the next Read triggers EnsureAvailable at the
// new position, the same "focus" mechanic DownloadSession's range tracking already uses for HTTP
// Range seeks. mpv always issues a seek to 0 immediately after open (to probe seekability), so
// this must succeed for offset 0 unconditionally.
func (s *StreamInstance) Seek(offset int64) (int64, error) {
	size := s.src.Size()
	if offset < 0 || offset > size {
		return 0, fmt.Errorf("stream instance: seek offset %d out of range [0,%d]", offset, size)
	}
	s.mu.Lock()
	s.pos = offset
	s.mu.Unlock()
	return offset, nil
}

func (s *StreamInstance) Size() int64 { return s.src.Size() }

// Cancel interrupts whatever Read is currently blocked in EnsureAvailable. Must be safe to call
// concurrently from a thread other than the one running Read/Seek and must not block — this is
// mpv's cancel_fn contract exactly (called from a separate thread than the demux thread).
func (s *StreamInstance) Cancel() {
	s.mu.Lock()
	cancel := s.cancel
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// Close releases this stream instance's own resources (its local file handle, any in-flight
// wait). It does NOT tear down the underlying ByteSource/DownloadSession — that's owned by the
// playback session's lifecycle (ox_stop_playback), exactly as one HTTP bridge connection ending
// does not cancel the download for other connections still reading the same session.
func (s *StreamInstance) Close() {
	s.Cancel()
	if s.file != nil {
		_ = s.file.Close()
	}
}
