package oxtelegram

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureAvailable_inWindowShortCircuit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "part")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	d := &DownloadSession{
		ref:       &VideoFileRef{Size: 10_000_000},
		file:      f,
		ranges:    []byteRange{{start: 1_000_000, end: 2_000_000}},
		lastFocus: 1_100_000,
	}
	if err := d.EnsureAvailable(context.Background(), 1_100_000, 100); err != nil {
		t.Fatalf("in-window should no-op: %v", err)
	}
	if len(d.ranges) != 1 || d.ranges[0].start != 1_000_000 || d.ranges[0].end != 2_000_000 {
		t.Fatalf("ranges mutated: %+v", d.ranges)
	}
}

func TestEnsureAvailable_clampNeedEndPastEof(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 100_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: 50_000, end: size}},
		lastFocus: 60_000,
	}
	if err := d.EnsureAvailable(context.Background(), 60_000, 512*1024); err != nil {
		t.Fatalf("clamped in-window past-EOF request should succeed: %v", err)
	}
}

func TestEnsureAvailable_wholeFileCompleteShortCircuit(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 5_000_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: 0, end: size}},
		complete:  true,
		lastFocus: size / 2,
	}
	if err := d.EnsureAvailable(context.Background(), size/2, 100); err != nil {
		t.Fatalf("whole-file complete should no-op: %v", err)
	}
}

func TestEnsureAvailable_eofCuePreservedOnMidSeek(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, "part"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	const size int64 = 1024 * 1024
	cueStart := size - 100_000
	d := &DownloadSession{
		ref:       &VideoFileRef{Size: size},
		file:      f,
		ranges:    []byteRange{{start: cueStart, end: size}},
		complete:  false,
		lastFocus: cueStart,
	}

	// Mid-file EnsureAvailable must NOT wipe the EOF cue range (old single-window reset did).
	// Without network it cannot fill mid — but holesLocked/merge path must keep cue.
	d.mu.Lock()
	holes := d.holesLocked(alignDown(size/2, downloadChunkSize), size/2+1)
	cueStill := d.coversLocked(cueStart, size)
	d.mu.Unlock()
	if len(holes) == 0 {
		t.Fatal("mid-file should still be a hole")
	}
	if !cueStill {
		t.Fatal("EOF cue range must remain covered after mid-file hole query")
	}
}

func TestMergeRanges_adjacentAndOverlap(t *testing.T) {
	d := &DownloadSession{ref: &VideoFileRef{Size: 10_000}}
	d.mergeRangeLocked(0, 100)
	d.mergeRangeLocked(100, 200) // adjacent
	d.mergeRangeLocked(150, 300) // overlap
	d.mergeRangeLocked(1000, 1100)
	if len(d.ranges) != 2 {
		t.Fatalf("want 2 ranges, got %+v", d.ranges)
	}
	if d.ranges[0].start != 0 || d.ranges[0].end != 300 {
		t.Fatalf("first range %+v", d.ranges[0])
	}
	if d.ranges[1].start != 1000 || d.ranges[1].end != 1100 {
		t.Fatalf("second range %+v", d.ranges[1])
	}
}

func TestHolesLocked(t *testing.T) {
	d := &DownloadSession{
		ref:    &VideoFileRef{Size: 1000},
		ranges: []byteRange{{start: 100, end: 200}, {start: 400, end: 500}},
	}
	holes := d.holesLocked(0, 600)
	want := []byteRange{{0, 100}, {200, 400}, {500, 600}}
	if len(holes) != len(want) {
		t.Fatalf("holes=%+v want=%+v", holes, want)
	}
	for i := range want {
		if holes[i] != want[i] {
			t.Fatalf("hole[%d]=%+v want %+v", i, holes[i], want[i])
		}
	}
}
