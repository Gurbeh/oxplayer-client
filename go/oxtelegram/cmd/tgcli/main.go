// tgcli is a manual end-to-end test harness for go/oxtelegram, using the exact production code
// path (oxtelegram.Client) — not a special test-only path. See plan Phase 1 verify step.
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"

	"oxtelegram"
)

type stdoutSink struct{}

func (stdoutSink) OnAuthStateChanged(kind, qrLoginURL, passwordHint, errorMessage string) {
	fmt.Printf("[auth] state=%s", kind)
	if qrLoginURL != "" {
		fmt.Printf(" qrUrl=%s", qrLoginURL)
	}
	if passwordHint != "" {
		fmt.Printf(" hint=%s", passwordHint)
	}
	if errorMessage != "" {
		fmt.Printf(" err=%s", errorMessage)
	}
	fmt.Println()
}

func prompt(r *bufio.Reader, label string) string {
	fmt.Print(label)
	line, _ := r.ReadString('\n')
	for len(line) > 0 && (line[len(line)-1] == '\n' || line[len(line)-1] == '\r') {
		line = line[:len(line)-1]
	}
	return line
}

func main() {
	apiIDStr := os.Getenv("TELEGRAM_API_ID")
	apiHash := os.Getenv("TELEGRAM_API_HASH")
	sessionPath := flag.String("session", "tgcli.session", "path to session file")
	channel := flag.String("channel", "", "public channel username to resolve (without @)")
	messageID := flag.Int64("message", 0, "message id to resolve within -channel")
	flag.Parse()

	if apiIDStr == "" || apiHash == "" {
		fmt.Fprintln(os.Stderr, "set TELEGRAM_API_ID and TELEGRAM_API_HASH")
		os.Exit(1)
	}
	apiID, err := strconv.Atoi(apiIDStr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid TELEGRAM_API_ID:", err)
		os.Exit(1)
	}

	storage := oxtelegram.NewFileSessionStorage(*sessionPath)
	client := oxtelegram.NewClient(apiID, apiHash, storage)

	ctx := context.Background()
	var lastState string
	sink := authSinkFunc(func(kind, qrURL, hint, errMsg string) {
		lastState = kind
		stdoutSink{}.OnAuthStateChanged(kind, qrURL, hint, errMsg)
	})

	fmt.Println("configuring client...")
	if err := client.Configure(ctx, sink); err != nil {
		fmt.Fprintln(os.Stderr, "configure failed:", err)
		os.Exit(1)
	}
	defer client.Close()

	r := bufio.NewReader(os.Stdin)
	if lastState == string(oxtelegram.AuthWaitingForPhoneNumber) {
		phone := prompt(r, "phone (+countrycode...): ")
		if err := client.Auth.SubmitPhoneNumber(ctx, phone); err != nil {
			fmt.Fprintln(os.Stderr, "SubmitPhoneNumber failed:", err)
			os.Exit(1)
		}
		if lastState == string(oxtelegram.AuthWaitingForCode) {
			code := prompt(r, "code: ")
			if err := client.Auth.SubmitCode(ctx, code); err != nil {
				fmt.Fprintln(os.Stderr, "SubmitCode failed:", err)
				os.Exit(1)
			}
		}
		if lastState == string(oxtelegram.AuthWaitingForPassword) {
			password := prompt(r, "2FA password: ")
			if err := client.Auth.SubmitTwoFactorPassword(ctx, password); err != nil {
				fmt.Fprintln(os.Stderr, "SubmitTwoFactorPassword failed:", err)
				os.Exit(1)
			}
		}
	}

	if lastState != string(oxtelegram.AuthReady) {
		fmt.Fprintln(os.Stderr, "did not reach ready state, last =", lastState)
		os.Exit(1)
	}
	fmt.Println("READY — session persisted to", *sessionPath)

	if *channel != "" && *messageID != 0 {
		api := client.API()
		if api == nil {
			fmt.Fprintln(os.Stderr, "no API client available")
			os.Exit(1)
		}
		fmt.Printf("resolving @%s message %d...\n", *channel, *messageID)
		// Phase 3 will do this properly (multi-DC, CDN, cancellation) — tgcli just proves
		// Configure/Auth/session persistence for Phase 1, so this stays a placeholder note.
		fmt.Println("(resolve/download exercised separately once Phase 3 lands)")
	}
}

type authSinkFunc func(kind, qrLoginURL, passwordHint, errorMessage string)

func (f authSinkFunc) OnAuthStateChanged(kind, qrLoginURL, passwordHint, errorMessage string) {
	f(kind, qrLoginURL, passwordHint, errorMessage)
}
