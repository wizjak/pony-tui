package main

import (
	"encoding/json"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// startFake runs a minimal fake Discord IPC server on a temp unix socket.
// It answers the handshake with READY and replies to SET_ACTIVITY (with an
// ERROR event when failActivity is true). The received SET_ACTIVITY request
// is delivered on the returned channel.
func startFake(t *testing.T, failActivity bool) (string, <-chan map[string]any) {
	t.Helper()
	sock := filepath.Join(t.TempDir(), "discord-ipc-0")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Skipf("cannot listen on a unix socket here: %v", err)
	}
	t.Cleanup(func() { ln.Close() })

	got := make(chan map[string]any, 1)
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()

		op, data, err := readFrame(c)
		if err != nil || op != opHandshake {
			return
		}
		var hs map[string]any
		_ = json.Unmarshal(data, &hs)
		if hs["client_id"] != "123" {
			return
		}
		_ = writeFrame(c, opFrame, []byte(`{"cmd":"DISPATCH","evt":"READY","data":{}}`))

		op, data, err = readFrame(c)
		if err != nil || op != opFrame {
			return
		}
		var req map[string]any
		_ = json.Unmarshal(data, &req)
		got <- req

		reply := map[string]any{"cmd": "SET_ACTIVITY", "evt": nil, "nonce": req["nonce"], "data": map[string]any{}}
		if failActivity {
			reply["evt"] = "ERROR"
			reply["data"] = map[string]any{"code": 4000, "message": "bad activity"}
		}
		out, _ := json.Marshal(reply)
		_ = writeFrame(c, opFrame, out)
	}()
	return sock, got
}

func TestHandshakeAndSetActivity(t *testing.T) {
	sock, got := startFake(t, false)

	c, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if err := handshake(c, "123"); err != nil {
		t.Fatalf("handshake: %v", err)
	}
	act := &Activity{
		Details: "Hello",
		State:   "World",
		Buttons: []Button{{Label: "Get pony-tui", URL: "https://example.com"}},
	}
	if err := setActivity(c, act); err != nil {
		t.Fatalf("setActivity: %v", err)
	}

	select {
	case req := <-got:
		if req["cmd"] != "SET_ACTIVITY" {
			t.Fatalf("unexpected cmd: %v", req["cmd"])
		}
		args, _ := req["args"].(map[string]any)
		a, _ := args["activity"].(map[string]any)
		if a["details"] != "Hello" || a["state"] != "World" {
			t.Fatalf("unexpected activity: %v", a)
		}
		if _, ok := a["buttons"]; !ok {
			t.Fatalf("buttons missing from activity: %v", a)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("fake server never received SET_ACTIVITY")
	}
}

func TestSetActivityError(t *testing.T) {
	sock, _ := startFake(t, true)

	c, err := net.Dial("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if err := handshake(c, "123"); err != nil {
		t.Fatalf("handshake: %v", err)
	}
	err = setActivity(c, &Activity{Details: "Hello"})
	if err == nil || !strings.Contains(err.Error(), "bad activity") {
		t.Fatalf("expected the ERROR event to surface, got: %v", err)
	}
}

func TestFix(t *testing.T) {
	if got := fix("  hi  ", 10); got != "hi" {
		t.Fatalf("got %q", got)
	}
	if got := fix("a", 10); len([]rune(got)) < 2 {
		t.Fatalf("single-character field must be padded, got %q", got)
	}
	long := strings.Repeat("x", 200)
	if got := fix(long, 128); len([]rune(got)) != 128 {
		t.Fatalf("expected 128 runes, got %d", len([]rune(got)))
	}
}

func TestCandidateSocketsOverride(t *testing.T) {
	got := candidateSockets("/tmp/custom-ipc")
	if len(got) != 1 || got[0] != "/tmp/custom-ipc" {
		t.Fatalf("unexpected candidates: %v", got)
	}
}
