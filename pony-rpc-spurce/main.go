// pony-rpc — tiny Discord Rich Presence helper for pony-tui.
//
// It talks to the local Discord client (or Vesktop/Equibop via arRPC) over the
// discord-ipc unix socket, shows what you're watching, and adds a button that
// links to the pony-tui repository. It runs until it receives SIGINT/SIGTERM
// (or until the process given with -parent exits), then clears the presence.
//
// Example:
//
//	pony-rpc -details "Friendship is Magic, Part 1" -state "Season 1 · Episode 1"
package main

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

const (
	defaultClientID = "1561841684801912902"
	defaultRepoURL  = "https://github.com/wizjak/pony-tui"
)

// IPC opcodes.
const (
	opHandshake uint32 = 0
	opFrame     uint32 = 1
	opClose     uint32 = 2
	opPing      uint32 = 3
	opPong      uint32 = 4
)

// --- activity payload ---------------------------------------------------------

type Button struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

type Assets struct {
	LargeImage string `json:"large_image,omitempty"`
	LargeText  string `json:"large_text,omitempty"`
}

type Timestamps struct {
	Start int64 `json:"start"`
}

type Activity struct {
	Type       int         `json:"type,omitempty"`
	Details    string      `json:"details,omitempty"`
	State      string      `json:"state,omitempty"`
	Timestamps *Timestamps `json:"timestamps,omitempty"`
	Assets     *Assets     `json:"assets,omitempty"`
	Buttons    []Button    `json:"buttons,omitempty"`
}

type response struct {
	Cmd   string          `json:"cmd"`
	Evt   string          `json:"evt"`
	Nonce string          `json:"nonce"`
	Data  json.RawMessage `json:"data"`
}

func (r response) errText() string {
	var d struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	if json.Unmarshal(r.Data, &d) == nil && d.Message != "" {
		return fmt.Sprintf("%s (code %d)", d.Message, d.Code)
	}
	return string(r.Data)
}

// --- options / logging --------------------------------------------------------

type options struct {
	clientID, details, state, image, imageText string
	btnLabel, btnURL, socket                   string
	typ, parent                                int
	start                                      int64
	quiet, noTimer, dryRun                     bool
}

var quiet bool

func logf(format string, a ...any) {
	if quiet {
		return
	}
	fmt.Fprintf(os.Stderr, "[pony-rpc] %s\n", fmt.Sprintf(format, a...))
}

// fix trims s, caps it at max runes and makes sure it is not a single
// character (Discord rejects 1-character fields).
func fix(s string, max int) string {
	r := []rune(strings.TrimSpace(s))
	if len(r) > max {
		r = append(r[:max-1], '…')
	}
	if len(r) == 1 {
		r = append(r, '\u200b')
	}
	return string(r)
}

func buildActivity(o options) *Activity {
	a := &Activity{
		Type:    o.typ,
		Details: fix(o.details, 128),
		State:   fix(o.state, 128),
	}
	if !o.noTimer {
		a.Timestamps = &Timestamps{Start: o.start}
	}
	if o.image != "" {
		a.Assets = &Assets{LargeImage: o.image, LargeText: fix(o.imageText, 128)}
	}
	if o.btnLabel != "" && o.btnURL != "" {
		a.Buttons = []Button{{Label: fix(o.btnLabel, 32), URL: o.btnURL}}
	}
	return a
}

// --- IPC framing --------------------------------------------------------------

func writeFrame(w io.Writer, op uint32, payload []byte) error {
	buf := make([]byte, 8+len(payload))
	binary.LittleEndian.PutUint32(buf[0:4], op)
	binary.LittleEndian.PutUint32(buf[4:8], uint32(len(payload)))
	copy(buf[8:], payload)
	_, err := w.Write(buf) // one write per frame
	return err
}

func readFrame(r io.Reader) (uint32, []byte, error) {
	var hdr [8]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return 0, nil, err
	}
	op := binary.LittleEndian.Uint32(hdr[0:4])
	n := binary.LittleEndian.Uint32(hdr[4:8])
	if n > 1<<20 {
		return 0, nil, fmt.Errorf("frame too large (%d bytes)", n)
	}
	data := make([]byte, n)
	if _, err := io.ReadFull(r, data); err != nil {
		return 0, nil, err
	}
	return op, data, nil
}

func newNonce() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// --- connecting ---------------------------------------------------------------

func candidateSockets(override string) []string {
	if override != "" {
		return []string{override}
	}
	var bases []string
	seenBase := map[string]bool{}
	for _, b := range []string{
		os.Getenv("XDG_RUNTIME_DIR"),
		os.Getenv("TMPDIR"),
		os.Getenv("TMP"),
		os.Getenv("TEMP"),
		fmt.Sprintf("/run/user/%d", os.Getuid()),
		"/tmp",
	} {
		if b != "" && !seenBase[b] {
			seenBase[b] = true
			bases = append(bases, b)
		}
	}
	// plain install, flatpak, snap, and a few sandboxed layouts
	patterns := []string{
		"discord-ipc-*",
		"app/*/discord-ipc-*",
		"snap.*/discord-ipc-*",
		".flatpak/*/xdg-run/discord-ipc-*",
	}
	var out []string
	seen := map[string]bool{}
	for _, b := range bases {
		for _, p := range patterns {
			matches, _ := filepath.Glob(filepath.Join(b, p))
			sort.Strings(matches)
			for _, m := range matches {
				if !seen[m] {
					seen[m] = true
					out = append(out, m)
				}
			}
		}
	}
	return out
}

func handshake(c net.Conn, clientID string) error {
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	defer c.SetDeadline(time.Time{})

	payload, _ := json.Marshal(map[string]any{"v": 1, "client_id": clientID})
	if err := writeFrame(c, opHandshake, payload); err != nil {
		return err
	}
	for {
		op, data, err := readFrame(c)
		if err != nil {
			return fmt.Errorf("handshake: %w", err)
		}
		switch op {
		case opClose:
			return fmt.Errorf("discord closed the connection: %s", data)
		case opPing:
			_ = writeFrame(c, opPong, data)
		case opFrame:
			var r response
			if json.Unmarshal(data, &r) == nil {
				switch r.Evt {
				case "READY":
					return nil
				case "ERROR":
					return fmt.Errorf("handshake error: %s", r.errText())
				}
			}
		}
	}
}

func connect(clientID, override string) (net.Conn, string, error) {
	paths := candidateSockets(override)
	if len(paths) == 0 {
		return nil, "", errors.New("no discord-ipc socket found (is Discord/Vesktop running, with Rich Presence enabled?)")
	}
	var lastErr error
	for _, p := range paths {
		c, err := net.DialTimeout("unix", p, 2*time.Second)
		if err != nil {
			lastErr = err
			continue
		}
		if err := handshake(c, clientID); err != nil {
			c.Close()
			lastErr = err
			continue
		}
		return c, p, nil
	}
	return nil, "", lastErr
}

// --- presence -----------------------------------------------------------------

func sendActivity(c net.Conn, act *Activity, nonce string) error {
	payload, err := json.Marshal(map[string]any{
		"cmd":   "SET_ACTIVITY",
		"args":  map[string]any{"pid": os.Getpid(), "activity": act}, // nil act clears the presence
		"nonce": nonce,
	})
	if err != nil {
		return err
	}
	return writeFrame(c, opFrame, payload)
}

// setActivity sends SET_ACTIVITY and waits for Discord's answer.
func setActivity(c net.Conn, act *Activity) error {
	nonce := newNonce()
	if err := sendActivity(c, act, nonce); err != nil {
		return err
	}
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	defer c.SetDeadline(time.Time{})
	for {
		op, data, err := readFrame(c)
		if err != nil {
			return err
		}
		switch op {
		case opClose:
			return fmt.Errorf("discord closed the connection: %s", data)
		case opPing:
			_ = writeFrame(c, opPong, data)
		case opFrame:
			var r response
			if json.Unmarshal(data, &r) != nil || r.Nonce != nonce {
				continue
			}
			if r.Evt == "ERROR" {
				return errors.New(r.errText())
			}
			return nil
		}
	}
}

// applyActivity sets the presence; if Discord refuses a non-default activity
// type (e.g. "Watching"), it retries as a plain "Playing" activity.
func applyActivity(c net.Conn, act *Activity) error {
	err := setActivity(c, act)
	if err != nil && act.Type != 0 {
		logf("discord rejected activity type %d (%v); retrying as plain \"Playing\"", act.Type, err)
		fallback := *act
		fallback.Type = 0
		return setActivity(c, &fallback)
	}
	return err
}

// hold keeps the connection alive (answers pings) until ctx ends or Discord drops us.
func hold(ctx context.Context, c net.Conn) error {
	errc := make(chan error, 1)
	go func() {
		for {
			op, data, err := readFrame(c)
			if err != nil {
				errc <- err
				return
			}
			switch op {
			case opPing:
				_ = writeFrame(c, opPong, data)
			case opClose:
				errc <- fmt.Errorf("discord closed the connection: %s", data)
				return
			}
		}
	}()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-errc:
		return err
	}
}

func sleepCtx(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}

func run(ctx context.Context, o options, act *Activity) {
	for ctx.Err() == nil {
		conn, path, err := connect(o.clientID, o.socket)
		if err != nil {
			logf("waiting for Discord… (%v)", err)
			sleepCtx(ctx, 5*time.Second)
			continue
		}
		logf("connected via %s", path)

		if err := applyActivity(conn, act); err != nil {
			logf("couldn't set the presence: %v", err)
			conn.Close()
			sleepCtx(ctx, 5*time.Second)
			continue
		}
		logf("presence is live: %q / %q", act.Details, act.State)

		err = hold(ctx, conn)
		if ctx.Err() != nil {
			_ = sendActivity(conn, nil, newNonce()) // clear it right away
			time.Sleep(200 * time.Millisecond)
			conn.Close()
			logf("presence cleared")
			return
		}
		logf("connection lost (%v); reconnecting…", err)
		conn.Close()
		sleepCtx(ctx, 3*time.Second)
	}
}

// watchParent cancels ctx once the process with the given pid is gone.
func watchParent(ctx context.Context, pid int, cancel context.CancelFunc) {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if err := syscall.Kill(pid, 0); err == syscall.ESRCH {
				cancel()
				return
			}
		}
	}
}

func main() {
	var o options
	flag.StringVar(&o.details, "details", "", "first line, e.g. the episode title")
	flag.StringVar(&o.state, "state", "", "second line, e.g. \"Season 1 · Episode 1\"")
	flag.IntVar(&o.typ, "type", 3, "activity type: 0 Playing, 2 Listening, 3 Watching (falls back to 0 if Discord refuses)")
	flag.StringVar(&o.image, "image", "pony", "large image asset key (upload it in the Developer Portal; empty = none)")
	flag.StringVar(&o.imageText, "image-text", "pony-tui", "tooltip of the large image")
	flag.StringVar(&o.btnLabel, "button-label", "Get pony-tui", "button label (max 32 chars; empty = no button)")
	flag.StringVar(&o.btnURL, "button-url", defaultRepoURL, "button link (empty = no button)")
	flag.BoolVar(&o.noTimer, "no-timer", false, "don't show the elapsed-time counter")
	flag.Int64Var(&o.start, "start", 0, "start time as a unix timestamp (default: now)")
	flag.IntVar(&o.parent, "parent", 0, "exit automatically when this PID exits")
	flag.StringVar(&o.clientID, "client-id", defaultClientID, "Discord application (client) ID")
	flag.StringVar(&o.socket, "socket", "", "path to the discord-ipc socket (auto-detected by default)")
	flag.BoolVar(&o.quiet, "q", false, "quiet: no log output")
	flag.BoolVar(&o.dryRun, "dry-run", false, "print the SET_ACTIVITY payload and exit (doesn't touch Discord)")
	flag.Parse()

	quiet = o.quiet
	if o.details == "" && o.state == "" {
		o.details = "Browsing episodes"
	}
	if o.start == 0 {
		o.start = time.Now().Unix()
	}
	act := buildActivity(o)

	if o.dryRun {
		out, _ := json.MarshalIndent(map[string]any{
			"cmd":  "SET_ACTIVITY",
			"args": map[string]any{"pid": os.Getpid(), "activity": act},
		}, "", "  ")
		fmt.Println(string(out))
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer stop()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if o.parent > 0 {
		go watchParent(ctx, o.parent, cancel)
	}

	run(ctx, o, act)
	logf("bye")
}
