package oxtelegram

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"strings"

	"github.com/gotd/td/tg"
)

// FetchWebAppInitData fetches a Telegram-signed Mini App initData payload for exchange with the
// backend's OX-account login endpoint (POST /auth/telegram). Ported from TDLib's
// GetWebAppLinkUrl -> GetWebAppUrl -> GetMainWebApp fallback chain
// (TdlibWebAppAuth.kt/fetchInitData) onto gotd/td's raw MTProto equivalents:
// messages.requestAppWebView (Direct Mini App link, needs webAppShortName) ->
// messages.requestWebView (hosted HTTPS Mini App) -> messages.requestMainWebView (bot's
// persistent "Main Mini App"). Since gotd/td is a 1:1 MTProto schema binding, this signing still
// happens entirely on Telegram's own servers via the logged-in user's real session — same
// security property as the TDLib version, no raw session credential ever leaves the device.
func (c *Client) FetchWebAppInitData(ctx context.Context, botUsername, webAppShortName, hostedHTTPSURL, platform string) (string, error) {
	api := c.API()
	if api == nil {
		return "", fmt.Errorf("client not configured")
	}
	if botUsername == "" {
		return "", fmt.Errorf("bot username not configured")
	}
	if platform == "" {
		platform = "android"
	}

	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{Username: botUsername})
	if err != nil {
		return "", fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	var botUser *tg.User
	for _, u := range resolved.Users {
		if user, ok := u.(*tg.User); ok {
			botUser = user
			break
		}
	}
	if botUser == nil {
		return "", fmt.Errorf("cannot resolve bot username %q to a user", botUsername)
	}

	inputUser := &tg.InputUser{UserID: botUser.ID, AccessHash: botUser.AccessHash}
	// The dialog where the web app is opened / result message would be sent — mirrors TDLib's
	// use of the bot's own private chat (CreatePrivateChat) for all three call variants, not the
	// user's currently-open chat (there isn't one in this headless resolve).
	inputPeer := &tg.InputPeerUser{UserID: botUser.ID, AccessHash: botUser.AccessHash}

	var webAppURL string
	var lastErr error

	if webAppShortName != "" {
		res, rerr := api.MessagesRequestAppWebView(ctx, &tg.MessagesRequestAppWebViewRequest{
			Peer:         inputPeer,
			App:          &tg.InputBotAppShortName{BotID: inputUser, ShortName: webAppShortName},
			Platform:     platform,
			WriteAllowed: true,
		})
		if rerr == nil {
			webAppURL = res.URL
		} else {
			lastErr = rerr
		}
	}

	if webAppURL == "" && hostedHTTPSURL != "" {
		res, rerr := api.MessagesRequestWebView(ctx, &tg.MessagesRequestWebViewRequest{
			Peer:     inputPeer,
			Bot:      inputUser,
			URL:      hostedHTTPSURL,
			Platform: platform,
		})
		if rerr == nil {
			webAppURL = res.URL
		} else {
			lastErr = rerr
		}
	}

	if webAppURL == "" {
		res, rerr := api.MessagesRequestMainWebView(ctx, &tg.MessagesRequestMainWebViewRequest{
			Peer:     inputPeer,
			Bot:      inputUser,
			Platform: platform,
		})
		if rerr == nil {
			webAppURL = res.URL
		} else {
			lastErr = rerr
		}
	}

	if webAppURL == "" {
		if lastErr != nil {
			return "", fmt.Errorf("cannot get WebApp URL from Telegram: %w", lastErr)
		}
		return "", fmt.Errorf("cannot get WebApp URL from Telegram")
	}

	log.Printf("oxtelegram: webapp URL = %s", webAppURL)

	data := extractTgWebAppData(webAppURL)
	if data == "" {
		return "", fmt.Errorf("tgWebAppData not found in WebApp URL from Telegram")
	}
	log.Printf("oxtelegram: extracted tgWebAppData = %s", data)
	return data, nil
}

// extractTgWebAppData mirrors TdlibWebAppAuth.kt's extraction: tgWebAppData may be a plain query
// param, or nested inside the URL fragment's own query string.
//
// Deliberately does NOT use net/url.URL.Query()/.Fragment (which auto-decode once) — tgWebAppData
// itself is a whole query string (query_id=...&user=...&auth_date=...&hash=...) that Telegram
// percent-encodes ONE level to become a single value. Reading it via an already-auto-decoded
// accessor and then running url.ParseQuery on that decodes it a SECOND time, which unescapes the
// tgWebAppData value's own internal %26/%3D into real &/= characters before ParseQuery ever gets
// to treat the whole thing as one opaque value — url.ParseQuery then splits on those now-literal
// separators and silently returns only the first field (query_id=...), dropping user/auth_date/
// hash entirely. The original Kotlin/TDLib version avoided this by reading Java URI's *raw*
// (undecoded) query/fragment accessors; this ports that by splitting the raw string manually
// instead of going through net/url for the outer split, so ParseQuery only ever decodes once.
func extractTgWebAppData(webAppURL string) string {
	if idx := strings.IndexByte(webAppURL, '?'); idx >= 0 {
		queryPart := webAppURL[idx+1:]
		if hashIdx := strings.IndexByte(queryPart, '#'); hashIdx >= 0 {
			queryPart = queryPart[:hashIdx]
		}
		if values, err := url.ParseQuery(queryPart); err == nil {
			if v := values.Get("tgWebAppData"); v != "" {
				return v
			}
		}
	}

	hashIdx := strings.IndexByte(webAppURL, '#')
	if hashIdx < 0 {
		return ""
	}
	values, err := url.ParseQuery(webAppURL[hashIdx+1:])
	if err != nil {
		return ""
	}
	return values.Get("tgWebAppData")
}
