package nixlog

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func render(t *testing.T, fixture string, width int, logs bool) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", fixture))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := NewRenderer(&out, width, logs).Consume(bytes.NewReader(data)); err != nil {
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
	if s, ok := ev.StringField(0); !ok || StoreName(s) != "hello-1.0" {
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

func TestStoreName(t *testing.T) {
	cases := map[string]string{
		"/nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hm-fixture-1.drv": "hm-fixture-1",
		"/nix/store/i0p3zh00jyq3l7hw8qm56mqak5pp3bs8-sl-5.05":          "sl-5.05",
		"short": "short",
	}
	for in, want := range cases {
		if got := StoreName(in); got != want {
			t.Errorf("StoreName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestPlainBuild(t *testing.T) {
	out := render(t, "build.jsonl", 0, false)
	want := "this derivation will be built:\n" +
		"  /nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hm-fixture-1794938904.drv\n" +
		"building '/nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-hm-fixture-1794938904.drv'\n"
	if out != want {
		t.Fatalf("plain output:\n%q\nwant:\n%q", out, want)
	}
}

func TestBuildLogs(t *testing.T) {
	out := render(t, "build.jsonl", 0, true)
	for _, line := range []string{"hm-fixture-1794938904> hello from build\n", "hm-fixture-1794938904> second line\n"} {
		if !strings.Contains(out, line) {
			t.Fatalf("missing %q in:\n%s", line, out)
		}
	}
}

func TestFailureMessage(t *testing.T) {
	out := render(t, "fail.jsonl", 0, false)
	if !strings.Contains(out, "builder failed with exit code 3") || !strings.Contains(out, "> about to fail") {
		t.Fatalf("failure not reported:\n%s", out)
	}
}

func TestPlainFetch(t *testing.T) {
	out := render(t, "fetch.jsonl", 0, false)
	if !strings.Contains(out, "copying path '/nix/store/i0p3zh00jyq3l7hw8qm56mqak5pp3bs8-sl-5.05' from 'https://cache.nixos.org'\n") {
		t.Fatalf("copy not reported:\n%s", out)
	}
	if strings.Contains(out, "downloading") || strings.Contains(out, "querying info") {
		t.Fatalf("talkative activities leaked into plain output:\n%s", out)
	}
}

func TestTTYStatus(t *testing.T) {
	out := render(t, "fetch.jsonl", 40, false)
	if strings.Contains(out, "copying path") {
		t.Fatalf("TTY output prints substitutions as lines:\n%q", out)
	}
	if !strings.Contains(out, "[fetched 0/1]") {
		t.Fatalf("TTY output has no fetch status:\n%q", out)
	}
	if !strings.HasSuffix(out, clearLine) {
		t.Fatalf("TTY output does not end by clearing the status line:\n%q", out)
	}
	for _, segment := range strings.Split(out, clearLine) {
		if !strings.Contains(segment, "\n") && len([]rune(segment)) >= 40 {
			t.Fatalf("status line not narrower than the terminal: %q", segment)
		}
	}
}

func TestStatus(t *testing.T) {
	s := NewState(Options{})
	events := []string{
		`@nix {"action":"start","id":1,"level":0,"type":104,"text":""}`,
		`@nix {"action":"result","id":1,"type":105,"fields":[1,3,1,0]}`,
		`@nix {"action":"start","id":2,"level":3,"type":105,"text":"building 'x'","fields":["/nix/store/lbn72v74by31g9w4dxxmw5ac1yklq6z6-foo-1.drv","",1,1]}`,
		`@nix {"action":"result","id":2,"type":104,"fields":["buildPhase"]}`,
	}
	for _, line := range events {
		ev, _, err := Parse([]byte(line))
		if err != nil {
			t.Fatal(err)
		}
		s.Apply(ev)
	}
	if got, want := s.Status(), "[built 1/3] building foo-1 (buildPhase)"; got != want {
		t.Fatalf("Status() = %q, want %q", got, want)
	}
	ev, _, _ := Parse([]byte(`@nix {"action":"stop","id":2}`))
	s.Apply(ev)
	if got, want := s.Status(), "[built 1/3]"; got != want {
		t.Fatalf("Status() after stop = %q, want %q", got, want)
	}
}

func TestMalformedLineIsReported(t *testing.T) {
	var out bytes.Buffer
	err := NewRenderer(&out, 0, false).Consume(strings.NewReader("@nix {broken\nplain\n"))
	if err == nil {
		t.Fatal("Consume swallowed a malformed event")
	}
	if out.String() != "@nix {broken\nplain\n" {
		t.Fatalf("lines not passed through: %q", out.String())
	}
}

func TestTruncate(t *testing.T) {
	if got := truncate("abcdef", 4); got != "abc…" {
		t.Fatalf("truncate = %q", got)
	}
	if got := truncate("abc", 4); got != "abc" {
		t.Fatalf("truncate = %q", got)
	}
}
