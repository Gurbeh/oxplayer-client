//go:build !windows

package oxtelegram

import "fmt"

// DPAPISessionStorage is Windows-only. This stub keeps non-Windows packages compiling.
type DPAPISessionStorage struct{}

func NewDPAPISessionStorage(path string) *DPAPISessionStorage {
	return &DPAPISessionStorage{}
}

func (d *DPAPISessionStorage) Load() ([]byte, error) {
	return nil, fmt.Errorf("DPAPISessionStorage is Windows-only")
}

func (d *DPAPISessionStorage) Store(data []byte) error {
	return fmt.Errorf("DPAPISessionStorage is Windows-only")
}

func (d *DPAPISessionStorage) Clear() error {
	return fmt.Errorf("DPAPISessionStorage is Windows-only")
}
