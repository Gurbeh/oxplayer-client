package oxtelegram

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"encoding/binary"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

const downloadChunkSize = 512 * 1024 // must stay a multiple of 4KB per upload.getFile's alignment rule

// byteRange is a half-open [start, end) contiguous downloaded region on the cache file.
type byteRange struct {
	start int64
	end   int64
}

// DownloadSession streams one file's bytes to a local cache file on demand, via raw
// upload.getFile chunk requests — mirrors TelegramFileDataSource's role but backed by this Go
// facade instead of TDLib's own file manager.
//
// Handles two distinct "this isn't on the connection you're talking to" cases, both required per
// the plan (not optional/best-effort): a FILE_MIGRATE_<n> RPC error routes to a pooled
// connection on the correct DC via Client.MediaOnly (which transfers authorization there
// automatically); a *tg.UploadFileCDNRedirect response (not an error) routes to a second
// protocol against a CDN DC (file tokens + AES-CTR decryption, ported from
// oxplayer-be/apps/ox-stream/internal/mtproto/cdn.go). Both routings are resolved once and
// cached on the session, not renegotiated per chunk.
//
// Downloaded coverage is a merged set of ranges (not a single window). MPV/HTTP often open a
// cue Range near EOF concurrently with a mid-file seek Range — resetting one window destroyed
// the other and caused ~minute seek stalls. Ranges keep both.
type DownloadSession struct {
	client *Client
	ref    *VideoFileRef

	mu sync.Mutex
	// ranges are sorted, non-overlapping, merged half-open intervals of bytes present on disk.
	ranges []byteRange
	// lastFocus is the offset of the most recent EnsureAvailable — AvailableFrom/AvailableUpTo
	// report the contiguous run covering this focus (HTTP bridge / Exo read cursors).
	lastFocus   int64
	file        *os.File
	complete    bool
	dcConn      telegram.CloseInvoker // set once a FILE_MIGRATE_<n> redirect is resolved
	cdnRedirect *tg.UploadFileCDNRedirect
}

// OpenDownload creates (or reopens) the local cache file for ref under cacheDir — the same file
// TelegramFileDataSource/TdlibHttpBridgeServer read from as bytes land.
func (c *Client) OpenDownload(ref *VideoFileRef, cacheDir string) (*DownloadSession, error) {
	if c.API() == nil {
		return nil, fmt.Errorf("client not configured")
	}
	path := filepath.Join(cacheDir, fmt.Sprintf("oxtelegram-%d.part", ref.DocumentID))
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open cache file: %w", err)
	}
	return &DownloadSession{client: c, ref: ref, file: f}, nil
}

func (d *DownloadSession) LocalPath() string { return d.file.Name() }
func (d *DownloadSession) TotalSize() int64  { return d.ref.Size }

// AvailableUpTo returns the end of the contiguous run covering lastFocus (see ranges doc).
func (d *DownloadSession) AvailableUpTo() int64 {
	d.mu.Lock()
	defer d.mu.Unlock()
	if r, ok := d.rangeCoveringLocked(d.lastFocus); ok {
		return r.end
	}
	return d.lastFocus
}

// AvailableFrom returns the start of the contiguous run covering lastFocus.
func (d *DownloadSession) AvailableFrom() int64 {
	d.mu.Lock()
	defer d.mu.Unlock()
	if r, ok := d.rangeCoveringLocked(d.lastFocus); ok {
		return r.start
	}
	return d.lastFocus
}

func (d *DownloadSession) IsComplete() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.isFullyCompleteLocked()
}

func (d *DownloadSession) isFullyCompleteLocked() bool {
	return d.complete || (len(d.ranges) == 1 && d.ranges[0].start == 0 && d.ranges[0].end >= d.ref.Size)
}

func (d *DownloadSession) rangeCoveringLocked(offset int64) (byteRange, bool) {
	for _, r := range d.ranges {
		if offset >= r.start && offset < r.end {
			return r, true
		}
	}
	return byteRange{}, false
}

func (d *DownloadSession) coversLocked(offset, needEnd int64) bool {
	if needEnd <= offset {
		return true
	}
	for _, r := range d.ranges {
		if offset >= r.start && needEnd <= r.end {
			return true
		}
	}
	return false
}

// holesLocked returns missing sub-ranges of [from, to) not yet on disk.
func (d *DownloadSession) holesLocked(from, to int64) []byteRange {
	if to <= from {
		return nil
	}
	var holes []byteRange
	cursor := from
	for _, r := range d.ranges {
		if r.end <= cursor {
			continue
		}
		if r.start >= to {
			break
		}
		if cursor < r.start {
			end := r.start
			if end > to {
				end = to
			}
			holes = append(holes, byteRange{start: cursor, end: end})
		}
		if r.end > cursor {
			cursor = r.end
		}
		if cursor >= to {
			return holes
		}
	}
	if cursor < to {
		holes = append(holes, byteRange{start: cursor, end: to})
	}
	return holes
}

func (d *DownloadSession) mergeRangeLocked(start, end int64) {
	if end <= start {
		return
	}
	n := byteRange{start: start, end: end}
	var out []byteRange
	merged := false
	for _, r := range d.ranges {
		if r.end < n.start {
			out = append(out, r)
			continue
		}
		if r.start > n.end {
			if !merged {
				out = append(out, n)
				merged = true
			}
			out = append(out, r)
			continue
		}
		// overlap / adjacent — merge
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
	d.ranges = out
	if len(d.ranges) == 1 && d.ranges[0].start == 0 && d.ranges[0].end >= d.ref.Size {
		d.complete = true
	}
}

// EnsureAvailable blocks until [offset, offset+length) is downloaded to the local cache file, or
// ctx is cancelled. Only missing holes are fetched — other ranges (e.g. EOF cues) are preserved.
func (d *DownloadSession) EnsureAvailable(ctx context.Context, offset, length int64) error {
	if length <= 0 {
		length = 1
	}
	if offset < 0 {
		return fmt.Errorf("ensureAvailable: negative offset %d", offset)
	}
	if offset >= d.ref.Size {
		return fmt.Errorf("ensureAvailable: offset %d past EOF %d", offset, d.ref.Size)
	}
	needEnd := offset + length
	if needEnd > d.ref.Size {
		needEnd = d.ref.Size
	}

	alignedFrom := alignDown(offset, downloadChunkSize)

	d.mu.Lock()
	d.lastFocus = offset
	if d.coversLocked(offset, needEnd) || d.isFullyCompleteLocked() {
		d.mu.Unlock()
		return nil
	}
	holes := d.holesLocked(alignedFrom, needEnd)
	d.mu.Unlock()

	for _, hole := range holes {
		pos := hole.start
		for pos < hole.end {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			d.mu.Lock()
			if d.coversLocked(offset, needEnd) {
				d.lastFocus = offset
				d.mu.Unlock()
				return nil
			}
			still := d.holesLocked(pos, hole.end)
			d.mu.Unlock()
			if len(still) == 0 {
				break
			}
			pos = still[0].start

			data, err := d.fetchChunk(ctx, pos, downloadChunkSize)
			if err != nil {
				return err
			}
			if len(data) > 0 {
				if _, err := d.file.WriteAt(data, pos); err != nil {
					return fmt.Errorf("write cache file: %w", err)
				}
			}

			wroteEnd := pos + int64(len(data))
			d.mu.Lock()
			d.mergeRangeLocked(pos, wroteEnd)
			d.lastFocus = offset
			done := d.coversLocked(offset, needEnd) || d.isFullyCompleteLocked()
			d.mu.Unlock()

			if done {
				return nil
			}
			if int64(len(data)) < downloadChunkSize || wroteEnd >= d.ref.Size {
				if wroteEnd < needEnd {
					return fmt.Errorf("ensureAvailable: EOF at %d before covering [%d,%d)", wroteEnd, offset, needEnd)
				}
				return nil
			}
			pos = wroteEnd
		}
	}

	d.mu.Lock()
	d.lastFocus = offset
	ok := d.coversLocked(offset, needEnd) || d.isFullyCompleteLocked()
	d.mu.Unlock()
	if !ok {
		return fmt.Errorf("ensureAvailable: failed to cover [%d,%d)", offset, needEnd)
	}
	return nil
}

// Cancel releases this session's resources (migrated-DC connection, local cache file handle).
// Does not delete the cache file — a subsequent OpenDownload for the same fileId resumes from
// whatever was already downloaded.
func (d *DownloadSession) Cancel() {
	d.mu.Lock()
	conn := d.dcConn
	d.dcConn = nil
	f := d.file
	d.mu.Unlock()

	if conn != nil {
		_ = conn.Close()
	}
	if f != nil {
		_ = f.Close()
	}
}

func alignDown(n, align int64) int64 {
	if align <= 0 {
		return n
	}
	return (n / align) * align
}

func (d *DownloadSession) location() *tg.InputDocumentFileLocation {
	return &tg.InputDocumentFileLocation{
		ID:            d.ref.DocumentID,
		AccessHash:    d.ref.AccessHash,
		FileReference: d.ref.FileReference,
	}
}

func (d *DownloadSession) fetchChunk(ctx context.Context, offset, limit int64) ([]byte, error) {
	d.mu.Lock()
	cdn := d.cdnRedirect
	conn := d.dcConn
	d.mu.Unlock()

	if cdn != nil {
		return d.fetchCDNChunk(ctx, cdn, offset, limit)
	}

	req := &tg.UploadGetFileRequest{Location: d.location(), Offset: offset, Limit: int(limit)}
	req.SetPrecise(true)
	req.SetCDNSupported(true)

	invoke := d.client.API().UploadGetFile
	if conn != nil {
		invoke = tg.NewClient(conn).UploadGetFile
	}

	start := time.Now()
	res, err := invoke(ctx, req)
	if took := time.Since(start); took > 500*time.Millisecond {
		log.Printf("oxtelegram: slow UploadGetFile offset=%d limit=%d tookMs=%d err=%v", offset, limit, took.Milliseconds(), err)
	}
	if dcID, ok := isFileMigrate(err); ok {
		log.Printf("oxtelegram: FILE_MIGRATE_%d for offset=%d, opening MediaOnly connection", dcID, offset)
		migrateStart := time.Now()
		mediaConn, mErr := d.client.mediaOnlyDC(ctx, dcID)
		log.Printf("oxtelegram: MediaOnly DC=%d tookMs=%d err=%v", dcID, time.Since(migrateStart).Milliseconds(), mErr)
		if mErr != nil {
			return nil, fmt.Errorf("migrate to DC %d: %w", dcID, mErr)
		}
		d.mu.Lock()
		d.dcConn = mediaConn
		d.mu.Unlock()
		res, err = tg.NewClient(mediaConn).UploadGetFile(ctx, req)
	}
	if err != nil {
		return nil, fmt.Errorf("UploadGetFile: %w", err)
	}

	switch v := res.(type) {
	case *tg.UploadFile:
		return v.Bytes, nil
	case *tg.UploadFileCDNRedirect:
		log.Printf("oxtelegram: CDN redirect for offset=%d, switching to upload.getCdnFile", offset)
		d.mu.Lock()
		d.cdnRedirect = v
		d.mu.Unlock()
		return d.fetchCDNChunk(ctx, v, offset, limit)
	default:
		return nil, fmt.Errorf("unexpected upload.getFile response %T", res)
	}
}

func isFileMigrate(err error) (int, bool) {
	rpcErr, ok := tgerr.AsType(err, "FILE_MIGRATE")
	if !ok {
		return 0, false
	}
	return rpcErr.Argument, true
}

// --- CDN path: ported from oxplayer-be/apps/ox-stream/internal/mtproto/cdn.go, same protocol
// requirement (https://core.telegram.org/cdn) — if the CDN DC hasn't received this file part yet
// (cdnFileReuploadNeeded), the MASTER DC must be asked to push it there (upload.reuploadCdnFile)
// before a retry succeeds. Without this step, a fresh redirect can loop forever with no error.

var errCDNTokenExpired = fmt.Errorf("cdn file token expired")

func (d *DownloadSession) fetchCDNChunk(ctx context.Context, redirect *tg.UploadFileCDNRedirect, offset, limit int64) ([]byte, error) {
	master := d.client.API()

	data, requestToken, err := getCDNFile(ctx, master, redirect, offset, limit)
	if err != nil {
		return nil, err
	}
	if requestToken == nil {
		return data, nil
	}

	if _, err := master.UploadReuploadCDNFile(ctx, &tg.UploadReuploadCDNFileRequest{
		FileToken:    redirect.FileToken,
		RequestToken: requestToken,
	}); err != nil {
		return nil, fmt.Errorf("upload.reuploadCdnFile: %w", err)
	}

	data, requestToken, err = getCDNFile(ctx, master, redirect, offset, limit)
	if err != nil {
		return nil, err
	}
	if requestToken != nil {
		return nil, errCDNTokenExpired
	}
	return data, nil
}

func getCDNFile(ctx context.Context, api *tg.Client, redirect *tg.UploadFileCDNRedirect, offset, limit int64) ([]byte, []byte, error) {
	res, err := api.UploadGetCDNFile(ctx, &tg.UploadGetCDNFileRequest{
		Offset:    offset,
		Limit:     int(limit),
		FileToken: redirect.FileToken,
	})
	if err != nil {
		return nil, nil, err
	}
	switch out := res.(type) {
	case *tg.UploadCDNFile:
		data, err := decryptCDNBytes(out.Bytes, redirect, offset)
		return data, nil, err
	case *tg.UploadCDNFileReuploadNeeded:
		return nil, out.RequestToken, nil
	default:
		return nil, nil, fmt.Errorf("unexpected upload.getCdnFile type %T", res)
	}
}

func decryptCDNBytes(src []byte, redirect *tg.UploadFileCDNRedirect, offset int64) ([]byte, error) {
	block, err := aes.NewCipher(redirect.EncryptionKey)
	if err != nil {
		return nil, err
	}
	if block.BlockSize() != len(redirect.EncryptionIv) {
		return nil, fmt.Errorf("invalid CDN IV length")
	}
	iv := make([]byte, len(redirect.EncryptionIv))
	copy(iv, redirect.EncryptionIv)
	binary.BigEndian.PutUint32(iv[len(iv)-4:], uint32(offset/16))
	dst := make([]byte, len(src))
	cipher.NewCTR(block, iv).XORKeyStream(dst, src)
	return dst, nil
}
