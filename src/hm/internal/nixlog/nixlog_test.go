package nixlog

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

var epoch = time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC)

func fixedClock(t *time.Time) func() time.Time {
	return func() time.Time { return *t }
}

func render(t *testing.T, fixture string, cfg Config) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", fixture))
	if err != nil {
		t.Fatal(err)
	}
	now := epoch
	cfg.Now = fixedClock(&now)
	var out bytes.Buffer
	if err := NewRenderer(&out, cfg).Consume(bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	return out.String()
}

func TestParse(t *testing.T) {
	ev, ok, err := Parse([]byte(`@nix {"action":"start","fields":["/nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hello-1.0.drv","",1,1],"id":7,"level":3,"parent":2,"text":"building","type":105}`))
	if err != nil || !ok {
		t.Fatalf("Parse: ok=%v err=%v", ok, err)
	}
	if ev.Action != ActionStart || ev.ID != 7 || ev.Parent != 2 || ActivityType(ev.Type) != ActivityBuild || ev.Level != LevelInfo {
		t.Fatalf("unexpected event %+v", ev)
	}
	if s, ok := ev.StringField(0); !ok || !strings.HasSuffix(s, "-hello-1.0.drv") {
		t.Fatalf("StringField(0) = %q, %v", s, ok)
	}
	if n, ok := ev.IntField(2); !ok || n != 1 {
		t.Fatalf("IntField(2) = %d, %v", n, ok)
	}
	if _, ok := ev.IntField(1); ok {
		t.Fatal("IntField on a string field succeeded")
	}
	if _, ok := ev.StringField(9); ok {
		t.Fatal("StringField out of range succeeded")
	}

	if _, ok, err := Parse([]byte("warning: plain line")); ok || err != nil {
		t.Fatalf("plain line: ok=%v err=%v", ok, err)
	}
	if _, ok, err := Parse([]byte(`@nix {"action":"bogus"}`)); !ok || err == nil {
		t.Fatalf("unknown action: ok=%v err=%v", ok, err)
	}
	if _, ok, err := Parse([]byte(`@nix {not json`)); !ok || err == nil {
		t.Fatalf("malformed: ok=%v err=%v", ok, err)
	}
}

func TestPlainBuild(t *testing.T) {
	out := render(t, "build.jsonl", Config{})
	want := "this derivation will be built:\n" +
		"  /nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hm-fixture-1794938904.drv\n" +
		"building '/nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hm-fixture-1794938904.drv'\n"
	if out != want {
		t.Fatalf("plain output:\n%q\nwant:\n%q", out, want)
	}
}

func TestBuildLogs(t *testing.T) {
	out := render(t, "build.jsonl", Config{BuildLogs: true})
	for _, line := range []string{"hm-fixture-1794938904> hello from build\n", "hm-fixture-1794938904> second line\n"} {
		if !strings.Contains(out, line) {
			t.Fatalf("missing %q in:\n%s", line, out)
		}
	}
}

func TestFailureMessage(t *testing.T) {
	out := render(t, "fail.jsonl", Config{})
	if !strings.Contains(out, "builder failed with exit code 3") || !strings.Contains(out, "> about to fail") {
		t.Fatalf("failure not reported:\n%s", out)
	}
}

func TestPlainFetch(t *testing.T) {
	out := render(t, "fetch.jsonl", Config{})
	if !strings.Contains(out, "copying path '/nix/store/i0p3zh00jyq3l7hw8qm56mqak5pp3bs8-sl-5.05' from 'https://cache.nixos.org'\n") {
		t.Fatalf("copy not reported:\n%s", out)
	}
	if strings.Contains(out, "downloading") || strings.Contains(out, "querying info") {
		t.Fatalf("talkative activities leaked into plain output:\n%s", out)
	}
}

func TestLiveFetch(t *testing.T) {
	const width = 40
	out := render(t, "fetch.jsonl", Config{Width: width, Height: 20})
	if strings.Contains(out, "copying path") || strings.Contains(out, "will be fetched") {
		t.Fatalf("live output prints what the frame shows:\n%q", out)
	}
	if !strings.HasPrefix(out, hideCursor) || !strings.HasSuffix(out, showCursor) {
		t.Fatalf("live output does not hide and restore the cursor:\n%q", out)
	}
	ic := ui.Unicode
	if !strings.Contains(out, ic.With(ic.Done, "Finished in 0s: fetched 1")+"\n") {
		t.Fatalf("no final summary:\n%q", out)
	}
	for _, segment := range strings.Split(out, "\n") {
		for _, line := range strings.Split(segment, clearToEnd) {
			if ui.Width(line) >= width {
				t.Fatalf("frame line not narrower than the terminal: %q", line)
			}
		}
	}
}

type watchedBuffer struct {
	mu     sync.Mutex
	buf    bytes.Buffer
	writes chan struct{}
}

func (w *watchedBuffer) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	n, err := w.buf.Write(p)
	select {
	case w.writes <- struct{}{}:
	default:
	}
	return n, err
}

func (w *watchedBuffer) waitFor(t *testing.T, want string) {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		w.mu.Lock()
		found := strings.Contains(w.buf.String(), want)
		w.mu.Unlock()
		if found {
			return
		}
		select {
		case <-w.writes:
		case <-deadline:
			t.Fatalf("output never contained %q", want)
		}
	}
}

func TestLiveFrameDrawsWhileStreaming(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "fetch.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.SplitAfter(string(data), "\n")
	split := slices.IndexFunc(lines, func(l string) bool {
		return strings.Contains(l, `"type":100}`) && strings.Contains(l, `"action":"start"`)
	}) + 1
	if split == 0 {
		t.Fatal("fetch.jsonl has no copy-path activity")
	}
	out := &watchedBuffer{writes: make(chan struct{}, 1)}
	in, feed := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- NewRenderer(out, Config{Width: 80, Height: 20}).Consume(in) }()
	if _, err := io.WriteString(feed, strings.Join(lines[:split], "")); err != nil {
		t.Fatal(err)
	}
	ic := ui.Unicode
	out.waitFor(t, "├─ "+ic.Download+ic.Gap+"sl-5.05")
	if _, err := io.WriteString(feed, strings.Join(lines[split:], "")); err != nil {
		t.Fatal(err)
	}
	feed.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	out.waitFor(t, clearToEnd+ic.With(ic.Done, "Finished in"))
}

func TestLiveFailure(t *testing.T) {
	out := render(t, "fail.jsonl", Config{Width: 80, Height: 20})
	ic := ui.Unicode
	if !strings.Contains(out, ic.With(ic.Failed, "1 failed build(s) after 0s")) {
		t.Fatalf("failed build not summarised:\n%q", out)
	}
	if !strings.Contains(out, "builder failed with exit code 3") {
		t.Fatalf("nix error not passed through:\n%q", out)
	}
}

func drvPath(name string) string {
	return "/nix/store/" + strings.Repeat("a", 32) + "-" + name + ".drv"
}

type replay struct {
	t     *testing.T
	state *State
	now   time.Time
}

func (r *replay) apply(lines ...string) {
	r.t.Helper()
	for _, line := range lines {
		ev, _, err := Parse([]byte(line))
		if err != nil {
			r.t.Fatal(err)
		}
		if _, err := r.state.Apply(ev, r.now); err != nil {
			r.t.Fatal(err)
		}
	}
}

func TestTree(t *testing.T) {
	inputs := map[string][]string{
		drvPath("system"): {drvPath("etc"), drvPath("kernel")},
		drvPath("etc"):    {drvPath("unit"), drvPath("unrelated-input")},
	}
	r := &replay{t: t, now: epoch, state: NewState(Options{Live: true, Inputs: func(p string) ([]string, error) { return inputs[p], nil }}, epoch)}
	r.apply(
		`@nix {"action":"msg","level":3,"msg":"these 4 derivations will be built:"}`,
		`@nix {"action":"msg","level":3,"msg":"  `+drvPath("unit")+`"}`,
		`@nix {"action":"msg","level":3,"msg":"  `+drvPath("kernel")+`"}`,
		`@nix {"action":"msg","level":3,"msg":"  `+drvPath("etc")+`"}`,
		`@nix {"action":"msg","level":3,"msg":"  `+drvPath("system")+`"}`,
		`@nix {"action":"start","id":1,"level":0,"type":104,"text":""}`,
		`@nix {"action":"result","id":1,"type":105,"fields":[0,4,2,0]}`,
		`@nix {"action":"start","id":2,"level":3,"type":105,"text":"","fields":["`+drvPath("unit")+`","",1,1]}`,
		`@nix {"action":"result","id":2,"type":104,"fields":["buildPhase"]}`,
		`@nix {"action":"start","id":3,"level":3,"type":105,"text":"","fields":["`+drvPath("kernel")+`","",1,1]}`,
	)
	r.now = epoch.Add(65 * time.Second)
	ic := ui.Unicode
	want := []string{
		"├─ " + ic.Planned + ic.Gap + "system",
		"│  ├─ " + ic.Running + ic.Gap + "kernel  " + ic.With(ic.Clock, "1m5s"),
		"│  ╰─ " + ic.Planned + ic.Gap + "etc",
		"│     ╰─ " + ic.Running + ic.Gap + "unit  buildPhase  " + ic.With(ic.Clock, "1m5s"),
		"┕━ " + ic.With(ic.Running, "2") + " " + ic.With(ic.Done, "0/4") + " " + ic.With(ic.Planned, "2") + " │ " + ic.With(ic.Clock, "1m5s"),
	}
	got := r.state.Frame(View{Width: 200, Height: 40}, r.now)
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("frame:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}

	flat := r.state.Frame(View{Width: 200, Height: 4}, r.now)
	if len(flat) != 3 || !strings.HasPrefix(flat[0], "├─ "+ic.Running) || !strings.Contains(flat[0], "kernel") || !strings.Contains(flat[1], "unit") {
		t.Fatalf("frame does not flatten into 4 rows:\n%s", strings.Join(flat, "\n"))
	}
	cut := r.state.Frame(View{Width: 200, Height: 3}, r.now)
	if len(cut) != 2 || cut[0] != "├─ … and 2 more" {
		t.Fatalf("frame does not cut down to 3 rows:\n%s", strings.Join(cut, "\n"))
	}

	r.apply(
		`@nix {"action":"stop","id":2}`,
		`@nix {"action":"msg","level":0,"msg":"\u001b[31;1merror:\u001b[0m Cannot build '\u001b[35;1m`+drvPath("kernel")+`\u001b[0m'."}`,
	)
	got = r.state.Frame(View{Width: 200, Height: 40}, r.now)
	if !strings.Contains(got[1], ic.With(ic.Failed, "kernel")) || strings.Contains(strings.Join(got, "\n"), "unit") {
		t.Fatalf("frame after unit finished and kernel failed:\n%s", strings.Join(got, "\n"))
	}
}

func TestWaitingChainsCollapse(t *testing.T) {
	names := []string{"system", "etc", "units", "hm", "files", "path", "leaf"}
	inputs := map[string][]string{}
	for i := 0; i+1 < len(names); i++ {
		inputs[drvPath(names[i])] = []string{drvPath(names[i+1])}
	}
	r := &replay{t: t, now: epoch, state: NewState(Options{Live: true, Inputs: func(p string) ([]string, error) { return inputs[p], nil }}, epoch)}
	r.apply(`@nix {"action":"msg","level":3,"msg":"these 7 derivations will be built:"}`)
	for _, n := range names {
		r.apply(`@nix {"action":"msg","level":3,"msg":"  ` + drvPath(n) + `"}`)
	}
	r.apply(`@nix {"action":"start","id":1,"level":3,"type":105,"text":"","fields":["` + drvPath("leaf") + `","",1,1]}`)
	ic := ui.Unicode
	want := []string{
		"├─ " + ic.Planned + ic.Gap + "system",
		"│  ├─ ⋮ 4 more",
		"│  ╰─ " + ic.Planned + ic.Gap + "path",
		"│     ╰─ " + ic.Running + ic.Gap + "leaf  " + ic.With(ic.Clock, "0s"),
	}
	got := r.state.Frame(View{Width: 200, Height: 40}, r.now)
	if strings.Join(got[:len(got)-1], "\n") != strings.Join(want, "\n") {
		t.Fatalf("frame:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestEstimates(t *testing.T) {
	r := &replay{t: t, now: epoch, state: NewState(Options{Live: true, Estimates: map[string]time.Duration{"linux": 3 * time.Minute}}, epoch)}
	r.apply(
		`@nix {"action":"start","id":1,"level":3,"type":105,"text":"","fields":["`+drvPath("linux-6.18.63")+`","",1,1]}`,
		`@nix {"action":"start","id":2,"level":3,"type":105,"text":"","fields":["`+drvPath("unit-x.service")+`","",1,1]}`,
	)
	r.now = epoch.Add(65 * time.Second)
	ic := ui.Unicode
	frame := strings.Join(r.state.Frame(View{Width: 200, Height: 20}, r.now), "\n")
	if !strings.Contains(frame, "linux-6.18.63  "+ic.With(ic.Clock, "1m5s / 3m0s")) || !strings.Contains(frame, "unit-x.service  "+ic.With(ic.Clock, "1m5s")+"\n") {
		t.Fatalf("estimates not shown:\n%s", frame)
	}
	r.apply(`@nix {"action":"stop","id":1}`)
	if got := r.state.Measured(); len(got) != 1 || got["linux"] != 65*time.Second {
		t.Fatalf("Measured() = %v", got)
	}
}

func TestResizeClearsReflowedFrame(t *testing.T) {
	var out bytes.Buffer
	now := epoch
	r := NewRenderer(&out, Config{Width: 80, Height: 20, Now: fixedClock(&now)})
	r.handle([]byte(`@nix {"action":"start","id":1,"level":3,"type":105,"text":"","fields":["` + drvPath(strings.Repeat("long-name-", 5)) + `","",1,1]}`))
	r.redraw()
	if len(r.widths) != 2 || r.widths[0] <= 40 {
		t.Fatalf("frame widths = %v", r.widths)
	}
	rows := (r.widths[0]+19)/20 + (r.widths[1]+19)/20
	r.flush()
	out.Reset()
	r.resize(ui.Size{Width: 20, Height: 20})
	r.clearFrame()
	r.flush()
	if want := "\r\x1b[" + strconv.Itoa(rows-1) + "A" + clearToEnd; out.String() != want {
		t.Fatalf("clear after resize = %q, want %q", out.String(), want)
	}
	r.redraw()
	for _, w := range r.widths {
		if w >= 20 {
			t.Fatalf("frame redrawn wider than the new terminal: %v", r.widths)
		}
	}
}

func TestScreenRows(t *testing.T) {
	if got := screenRows([]int{0, 20, 21, 45}, 20); got != 1+1+2+3 {
		t.Fatalf("screenRows = %d", got)
	}
}

func TestFrameBeforeAnyEvent(t *testing.T) {
	s := NewState(Options{Live: true}, epoch)
	got := s.Frame(View{Width: 80, Height: 20}, epoch.Add(3*time.Second))
	if want := "╺━ " + ui.Unicode.With(ui.Unicode.Clock, "3s"); len(got) != 1 || got[0] != want {
		t.Fatalf("frame while evaluating = %q, want %q", got, want)
	}
	if _, ok := s.Summary(ui.Style{}, epoch); ok {
		t.Fatal("summary printed for a build that did nothing")
	}
}

func TestParseInputDrvs(t *testing.T) {
	drv := `Derive([("out","/nix/store/sd779x86bjaqxj2lzh2jsir4h0zjz6d1-hello-2.12.3","","")],` +
		`[("/nix/store/08grahh6i022hkpbaz3yix4wvrcrpyks-stdenv-linux.drv",["out"]),("/nix/store/kbpcpb1ps9sxn55ng7yifk6zmncrjifx-bash-5.3p20.drv",["out","dev"])],` +
		`["/nix/store/l622p70vy8k5sh7y5wizi5f2mic6ynpg-source-stdenv.sh"],"x86_64-linux","/bin/sh",["-e","a \"quoted\" ] arg"],[("name","hello")])`
	got, err := ParseInputDrvs([]byte(drv))
	if err != nil {
		t.Fatal(err)
	}
	want := "/nix/store/08grahh6i022hkpbaz3yix4wvrcrpyks-stdenv-linux.drv /nix/store/kbpcpb1ps9sxn55ng7yifk6zmncrjifx-bash-5.3p20.drv"
	if strings.Join(got, " ") != want {
		t.Fatalf("ParseInputDrvs = %q", got)
	}
	for _, bad := range []string{"", "Derive(", `Derive([("out"`, `Derive([],[("/nix/store/x.drv"`, "{}"} {
		if _, err := ParseInputDrvs([]byte(bad)); err == nil {
			t.Errorf("ParseInputDrvs(%q) succeeded", bad)
		}
	}
}

func TestMalformedLineIsReported(t *testing.T) {
	var out bytes.Buffer
	err := NewRenderer(&out, Config{}).Consume(strings.NewReader("@nix {broken\nplain\n"))
	if err == nil {
		t.Fatal("Consume swallowed a malformed event")
	}
	if out.String() != "@nix {broken\nplain\n" {
		t.Fatalf("lines not passed through: %q", out.String())
	}
}

func TestUnreadableDerivationIsReported(t *testing.T) {
	var out bytes.Buffer
	cfg := Config{Inputs: ReadInputDrvs}
	in := `@nix {"action":"msg","level":3,"msg":"this derivation will be built:"}` + "\n" +
		`@nix {"action":"msg","level":3,"msg":"  /nix/store/` + strings.Repeat("z", 32) + `-missing.drv"}` + "\n"
	if err := NewRenderer(&out, cfg).Consume(strings.NewReader(in)); err == nil || !strings.Contains(err.Error(), "missing.drv") {
		t.Fatalf("Consume err = %v", err)
	}
}
