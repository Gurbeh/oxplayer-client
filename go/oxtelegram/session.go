package oxtelegram

import (
	"context"

	"github.com/gotd/td/session"
)

// SessionStorage moves one opaque session blob in and out of whatever the host platform's
// secure storage is (Android EncryptedSharedPreferences/Keystore in Phase 2, a DPAPI-protected
// file on Windows in Phase 5). Deliberately just two methods — gotd/td's session.Storage is
// already this simple, unlike TDLib's on-disk SQLite+binlog+separate-encryption-key model.
type SessionStorage interface {
	Load() ([]byte, error)
	Store(data []byte) error
}

// sessionStorageAdapter adapts our gomobile-safe SessionStorage to gotd's session.Storage
// (which is context-aware; our host-side implementations never need a context since they're
// just reading/writing a local encrypted preference or file).
type sessionStorageAdapter struct {
	backing SessionStorage
}

var _ session.Storage = (*sessionStorageAdapter)(nil)

func (a *sessionStorageAdapter) LoadSession(_ context.Context) ([]byte, error) {
	return a.backing.Load()
}

func (a *sessionStorageAdapter) StoreSession(_ context.Context, data []byte) error {
	return a.backing.Store(data)
}

// FileSessionStorage is a plain-file-backed SessionStorage for desktop/CLI use (tgcli), where
// there's no platform-native secure storage to defer to. NOT used on Android/Windows in
// production — see Phase 2/5.
type FileSessionStorage struct {
	fs *session.FileStorage
}

func NewFileSessionStorage(path string) *FileSessionStorage {
	return &FileSessionStorage{fs: &session.FileStorage{Path: path}}
}

func (f *FileSessionStorage) Load() ([]byte, error) {
	return f.fs.LoadSession(context.Background())
}

func (f *FileSessionStorage) Store(data []byte) error {
	return f.fs.StoreSession(context.Background(), data)
}
