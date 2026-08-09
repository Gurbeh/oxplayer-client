//go:build windows

package oxtelegram

import (
	"fmt"
	"os"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

// DPAPISessionStorage persists the gotd session blob encrypted with Windows DPAPI
// (user-scope CryptProtectData). Plain file on disk is ciphertext only.
type DPAPISessionStorage struct {
	path string
}

func NewDPAPISessionStorage(path string) *DPAPISessionStorage {
	return &DPAPISessionStorage{path: path}
}

func (d *DPAPISessionStorage) Load() ([]byte, error) {
	raw, err := os.ReadFile(d.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	if len(raw) == 0 {
		return nil, nil
	}
	return dpapiUnprotect(raw)
}

func (d *DPAPISessionStorage) Store(data []byte) error {
	if err := os.MkdirAll(filepath.Dir(d.path), 0o700); err != nil {
		return err
	}
	sealed, err := dpapiProtect(data)
	if err != nil {
		return err
	}
	tmp := d.path + ".tmp"
	if err := os.WriteFile(tmp, sealed, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, d.path)
}

// Clear deletes the on-disk session (logout wipe).
func (d *DPAPISessionStorage) Clear() error {
	err := os.Remove(d.path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func newBlob(d []byte) *windows.DataBlob {
	if len(d) == 0 {
		return &windows.DataBlob{}
	}
	return &windows.DataBlob{
		Size: uint32(len(d)),
		Data: &d[0],
	}
}

func blobBytes(b *windows.DataBlob) []byte {
	if b == nil || b.Size == 0 || b.Data == nil {
		return nil
	}
	return unsafe.Slice(b.Data, b.Size)
}

func dpapiProtect(plain []byte) ([]byte, error) {
	in := newBlob(plain)
	var out windows.DataBlob
	err := windows.CryptProtectData(
		in,
		nil,
		nil,
		0,
		nil,
		windows.CRYPTPROTECT_UI_FORBIDDEN,
		&out,
	)
	if err != nil {
		return nil, fmt.Errorf("CryptProtectData: %w", err)
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	outBytes := blobBytes(&out)
	cp := make([]byte, len(outBytes))
	copy(cp, outBytes)
	return cp, nil
}

func dpapiUnprotect(sealed []byte) ([]byte, error) {
	in := newBlob(sealed)
	var out windows.DataBlob
	err := windows.CryptUnprotectData(
		in,
		nil,
		nil,
		0,
		nil,
		windows.CRYPTPROTECT_UI_FORBIDDEN,
		&out,
	)
	if err != nil {
		return nil, fmt.Errorf("CryptUnprotectData: %w", err)
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	outBytes := blobBytes(&out)
	cp := make([]byte, len(outBytes))
	copy(cp, outBytes)
	return cp, nil
}
