package oxtelegram

import "fmt"

// SessionURIRefersToFile reports whether a bridge session URI points at fileID
// (http://127.0.0.1:PORT/<id>). Used so stopPlayback ignores stale URIs after
// episode switches.
func SessionURIRefersToFile(uri string, fileID int) bool {
	if uri == "" || fileID <= 0 {
		return false
	}
	suffix := fmt.Sprintf("/%d", fileID)
	return len(uri) >= len(suffix) && uri[len(uri)-len(suffix):] == suffix
}
