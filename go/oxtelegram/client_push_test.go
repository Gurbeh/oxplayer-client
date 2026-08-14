package oxtelegram

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestDeliverPushedDocRemembersRefAndArmKeepsEarlyPush(t *testing.T) {
	c := NewClient(1, "hash", nil)
	c.pushArrived = make(map[string]pushArrival)
	c.pushWaiters = make(map[string]chan *pushedMessage)

	c.deliverPushedDoc("oxm_dev_459", &tg.Document{ID: 7}, 45825, 8998561851)
	ref := c.DeliveryRefForLocator("oxm_dev_459")
	if ref.MessageID != 45825 || ref.ProviderBotID != 8998561851 {
		t.Fatalf("push must remember delivery ref, got %+v", ref)
	}

	c.ArmDeliveryWaiter("oxm_dev_459")
	ch := c.registerPushWaiter("oxm_dev_459")
	select {
	case msg := <-ch:
		if msg.messageID != 45825 {
			t.Fatalf("messageID=%d", msg.messageID)
		}
	default:
		t.Fatal("ArmDeliveryWaiter dropped early push")
	}
}
