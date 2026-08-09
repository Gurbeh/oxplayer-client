package oxtelegram

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	httpBridgeReadChunk = 64 * 1024
	// Larger chunks = fewer reconnects on seek (Telegram MTProto TTFB is expensive).
	httpBridgeReadAhead   = 8 * 1024 * 1024
	httpBridgeOpenRange   = 8 * 1024 * 1024
	httpBridgeConnTimeout = 30 * time.Second
	// mpv closes old Range conn then opens new within ~ms; cancel must wait or it kills the seek.
	httpBridgeCancelGrace = 300 * time.Millisecond
)

// ByteSource is the progressive-download handle HttpBridgeServer reads from. DownloadSession
// satisfies this via DownloadByteSource; mobile.PlaybackSession adapts the same shape.
type ByteSource interface {
	Size() int64
	LocalPath() string
	AvailableFrom() int64
	AvailableUpTo() int64
	IsComplete() bool
	EnsureAvailable(ctx context.Context, offset, length int64) error
	CancelCurrentRead()
}

// DownloadByteSource adapts *DownloadSession to ByteSource. Concurrent HTTP Range
// requests each get their own cancel; CancelCurrentRead aborts all in-flight fetches
// (used when the last active bridge stream ends). Do not overwrite a single cancel —
// that made concurrent seeks cancel each other and stall playback.
type DownloadByteSource struct {
	dl *DownloadSession

	mu      sync.Mutex
	cancels []context.CancelFunc
}

func NewDownloadByteSource(dl *DownloadSession) *DownloadByteSource {
	return &DownloadByteSource{dl: dl}
}

func (s *DownloadByteSource) Size() int64          { return s.dl.TotalSize() }
func (s *DownloadByteSource) LocalPath() string    { return s.dl.LocalPath() }
func (s *DownloadByteSource) AvailableFrom() int64 { return s.dl.AvailableFrom() }
func (s *DownloadByteSource) AvailableUpTo() int64 { return s.dl.AvailableUpTo() }
func (s *DownloadByteSource) IsComplete() bool     { return s.dl.IsComplete() }

func (s *DownloadByteSource) EnsureAvailable(ctx context.Context, offset, length int64) error {
	ctx, cancel := context.WithCancel(ctx)
	s.mu.Lock()
	s.cancels = append(s.cancels, cancel)
	s.mu.Unlock()
	defer cancel()
	return s.dl.EnsureAvailable(ctx, offset, length)
}

func (s *DownloadByteSource) CancelCurrentRead() {
	s.mu.Lock()
	cancels := s.cancels
	s.cancels = nil
	s.mu.Unlock()
	for _, cancel := range cancels {
		cancel()
	}
}

// HttpBridgeServer is a loopback-only HTTP/1.1 Range server for libmpv/media_kit.
// 8MiB probe/open-ended Range, active refcount before EnsureAvailable, cancel grace on drain.
type HttpBridgeServer struct {
	mu        sync.Mutex
	sources   map[int]ByteSource
	ln        net.Listener
	port      int
	running   atomic.Bool
	active    atomic.Int32
	closed    chan struct{}
	closeOnce sync.Once
}

func NewHttpBridgeServer() *HttpBridgeServer {
	return &HttpBridgeServer{
		sources: make(map[int]ByteSource),
		closed:  make(chan struct{}),
	}
}

// Register binds fileID → source for URL path /{fileID}.
func (s *HttpBridgeServer) Register(fileID int, source ByteSource) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sources[fileID] = source
}

// Unregister removes a source. Does not close the underlying download.
func (s *HttpBridgeServer) Unregister(fileID int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sources, fileID)
}

func (s *HttpBridgeServer) lookup(fileID int) ByteSource {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sources[fileID]
}

// EnsureStarted binds 127.0.0.1:0 and starts the accept loop. Idempotent; returns bound port.
func (s *HttpBridgeServer) EnsureStarted() (int, error) {
	s.mu.Lock()
	if s.ln != nil {
		port := s.port
		s.mu.Unlock()
		return port, nil
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		s.mu.Unlock()
		return 0, err
	}
	s.ln = ln
	s.port = ln.Addr().(*net.TCPAddr).Port
	s.running.Store(true)
	port := s.port
	s.mu.Unlock()

	go s.acceptLoop(ln)
	return port, nil
}

// URLFor returns http://127.0.0.1:{port}/{fileID}, starting the server if needed.
func (s *HttpBridgeServer) URLFor(fileID int) (string, error) {
	port, err := s.EnsureStarted()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("http://127.0.0.1:%d/%d", port, fileID), nil
}

// Port returns the bound port or -1 if not started.
func (s *HttpBridgeServer) Port() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ln == nil {
		return -1
	}
	return s.port
}

// Close stops the accept loop and closes the listener.
func (s *HttpBridgeServer) Close() error {
	var err error
	s.closeOnce.Do(func() {
		s.running.Store(false)
		s.mu.Lock()
		ln := s.ln
		s.ln = nil
		s.mu.Unlock()
		if ln != nil {
			err = ln.Close()
		}
		close(s.closed)
	})
	return err
}

func (s *HttpBridgeServer) acceptLoop(ln net.Listener) {
	for s.running.Load() {
		conn, err := ln.Accept()
		if err != nil {
			if !s.running.Load() {
				return
			}
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			_ = c.SetDeadline(time.Now().Add(httpBridgeConnTimeout))
			s.handleConn(c)
		}(conn)
	}
}

func (s *HttpBridgeServer) handleConn(conn net.Conn) {
	br := bufio.NewReader(conn)
	line, err := br.ReadString('\n')
	if err != nil {
		return
	}
	parts := strings.Fields(strings.TrimSpace(line))
	if len(parts) < 2 {
		return
	}
	method, path := parts[0], parts[1]

	var rangeHeader string
	for {
		h, err := br.ReadString('\n')
		if err != nil {
			return
		}
		h = strings.TrimRight(h, "\r\n")
		if h == "" {
			break
		}
		if len(h) >= 6 && strings.EqualFold(h[:6], "Range:") {
			rangeHeader = strings.TrimSpace(h[6:])
		}
	}

	path = strings.TrimPrefix(path, "/")
	if i := strings.IndexByte(path, '?'); i >= 0 {
		path = path[:i]
	}
	fileID, err := strconv.Atoi(path)
	if err != nil {
		writeStatusOnly(conn, 404, "Not Found")
		return
	}
	src := s.lookup(fileID)
	if src == nil {
		writeStatusOnly(conn, 404, "Not Found")
		return
	}
	if method != "GET" && method != "HEAD" {
		writeStatusOnly(conn, 405, "Method Not Allowed")
		return
	}
	s.serveFile(conn, src, rangeHeader, method == "HEAD")
}

func parseRangeStart(rangeHeader string) int64 {
	if rangeHeader == "" {
		return 0
	}
	spec := strings.TrimPrefix(rangeHeader, "bytes=")
	startStr := strings.SplitN(spec, "-", 2)[0]
	n, err := strconv.ParseInt(startStr, 10, 64)
	if err != nil {
		return 0
	}
	return n
}

func parseRangeEnd(rangeHeader string, lastByte int64) (end int64, ok bool) {
	if rangeHeader == "" {
		return 0, false
	}
	spec := strings.TrimPrefix(rangeHeader, "bytes=")
	parts := strings.SplitN(spec, "-", 2)
	if len(parts) < 2 || parts[1] == "" {
		return 0, false
	}
	n, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, false
	}
	if n > lastByte {
		n = lastByte
	}
	return n, true
}

func (s *HttpBridgeServer) serveFile(w io.Writer, src ByteSource, rangeHeader string, headOnly bool) {
	start := parseRangeStart(rangeHeader)

	// Hold active before EnsureAvailable so a concurrent Connection-close cancel cannot
	// abort this seek's probe (mpv: close old Range → open new Range race).
	s.active.Add(1)
	defer func() {
		if s.active.Add(-1) > 0 {
			return
		}
		go func() {
			time.Sleep(httpBridgeCancelGrace)
			if s.active.Load() == 0 {
				src.CancelCurrentRead()
			}
		}()
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	probeWant := int64(httpBridgeReadAhead)
	if err := src.EnsureAvailable(ctx, start, probeWant); err != nil {
		writeStatusOnly(w, 500, "Internal Server Error")
		return
	}
	size := src.Size()
	if size <= 0 || start >= size {
		writeStatusOnly(w, 416, "Range Not Satisfiable")
		return
	}
	lastByte := size - 1
	explicitEnd, hasEnd := parseRangeEnd(rangeHeader, lastByte)
	var end int64
	switch {
	case hasEnd:
		end = explicitEnd
	default:
		end = start + httpBridgeOpenRange - 1
		if end > lastByte {
			end = lastByte
		}
	}
	contentLength := end - start + 1
	isPartial := rangeHeader != "" || end < lastByte

	var hdr strings.Builder
	if isPartial {
		hdr.WriteString("HTTP/1.1 206 Partial Content\r\n")
		fmt.Fprintf(&hdr, "Content-Range: bytes %d-%d/%d\r\n", start, end, size)
	} else {
		hdr.WriteString("HTTP/1.1 200 OK\r\n")
	}
	hdr.WriteString("Accept-Ranges: bytes\r\n")
	hdr.WriteString("Content-Type: application/octet-stream\r\n")
	fmt.Fprintf(&hdr, "Content-Length: %d\r\n", contentLength)
	hdr.WriteString("Connection: close\r\n")
	hdr.WriteString("\r\n")
	if _, err := io.WriteString(w, hdr.String()); err != nil {
		return
	}
	if headOnly || contentLength <= 0 {
		return
	}

	_ = streamRange(w, src, start, end, src.AvailableUpTo(), src.IsComplete())
}

func streamRange(w io.Writer, src ByteSource, start, end, knownUpTo int64, complete bool) error {
	f, err := os.Open(src.LocalPath())
	if err != nil {
		return err
	}
	defer f.Close()

	if _, err := f.Seek(start, io.SeekStart); err != nil {
		return err
	}
	buf := make([]byte, httpBridgeReadChunk)
	pos := start
	for pos <= end {
		want := int64(httpBridgeReadChunk)
		if rem := end - pos + 1; rem < want {
			want = rem
		}
		if !complete && pos+want > knownUpTo {
			// Prefetch a full read-ahead window, not one 64KiB chunk (seek stalls otherwise).
			prefetch := int64(httpBridgeReadAhead)
			if rem := end - pos + 1; rem > prefetch {
				prefetch = rem
			}
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			err := src.EnsureAvailable(ctx, pos, prefetch)
			cancel()
			if err != nil {
				return err
			}
			knownUpTo = src.AvailableUpTo()
			complete = src.IsComplete()
		}
		n, err := f.Read(buf[:want])
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return werr
			}
			pos += int64(n)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func writeStatusOnly(w io.Writer, code int, reason string) {
	_, _ = fmt.Fprintf(w, "HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", code, reason)
}

// ActiveStreams is exposed for tests.
func (s *HttpBridgeServer) ActiveStreams() int32 {
	return s.active.Load()
}
