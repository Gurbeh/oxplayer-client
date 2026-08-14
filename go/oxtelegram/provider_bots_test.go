package oxtelegram

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestPeerDialogHasMessages(t *testing.T) {
	t.Parallel()
	if peerDialogHasMessages(nil) {
		t.Fatal("nil result must be false")
	}
	if peerDialogHasMessages(&tg.MessagesPeerDialogs{}) {
		t.Fatal("empty dialogs must be false")
	}
	if peerDialogHasMessages(&tg.MessagesPeerDialogs{
		Dialogs: []tg.DialogClass{&tg.Dialog{TopMessage: 0}},
	}) {
		t.Fatal("empty peer after resolveUsername must not skip startBot")
	}
	if !peerDialogHasMessages(&tg.MessagesPeerDialogs{
		Dialogs: []tg.DialogClass{&tg.Dialog{TopMessage: 12}},
	}) {
		t.Fatal("TopMessage>0 must count as started")
	}
}
