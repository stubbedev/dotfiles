package ui

import (
	"bytes"
	"context"
	"errors"
	"os"
	"testing"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

func TestPaint(t *testing.T) {
	if got := (Style{}).Paint("x", Bold, Red); got != "x" {
		t.Fatalf("plain Paint = %q", got)
	}
	if got := NewStyle(true, nil).Paint("x", Bold, Red); got != "\x1b[1;31mx\x1b[0m" {
		t.Fatalf("colored Paint = %q", got)
	}
	if got := NewStyle(true, nil).Paint("", Bold); got != "" {
		t.Fatalf("empty Paint = %q", got)
	}
}

func TestWidthAndTruncate(t *testing.T) {
	st := NewStyle(true, nil)
	styled := st.Paint("héllo", Green) + " " + st.Paint("wörld", Red)
	if Width(styled) != 11 || Strip(styled) != "héllo wörld" {
		t.Fatalf("Width = %d, Strip = %q", Width(styled), Strip(styled))
	}
	if got := Truncate(styled, 7); Strip(got) != "héllo …" || got[len(got)-len(reset):] != reset {
		t.Fatalf("Truncate = %q", got)
	}
	if got := Truncate("short", 10); got != "short" {
		t.Fatalf("Truncate kept-width = %q", got)
	}
	if got := Truncate("abc", 0); got != "" {
		t.Fatalf("Truncate(0) = %q", got)
	}
}

func TestBytes(t *testing.T) {
	cases := map[int64]string{0: "0 B", 1023: "1023 B", 1536: "1.50 KiB", -3 << 20: "-3.00 MiB", 5 << 30: "5.00 GiB"}
	for in, want := range cases {
		if got := Bytes(in); got != want {
			t.Errorf("Bytes(%d) = %q, want %q", in, got, want)
		}
	}
}

func TestDetect(t *testing.T) {
	env := func(vars map[string]string) func(string) string {
		return func(k string) string { return vars[k] }
	}
	f, err := os.CreateTemp(t.TempDir(), "notatty")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if DetectColor(f, env(nil)) {
		t.Fatal("color on for a regular file")
	}
	if !DetectColor(f, env(map[string]string{"FORCE_COLOR": "1"})) {
		t.Fatal("FORCE_COLOR ignored")
	}
	if DetectColor(f, env(map[string]string{"FORCE_COLOR": "1", "NO_COLOR": "1"})) {
		t.Fatal("NO_COLOR does not win")
	}
	if DetectIcons(env(map[string]string{"TERM": "xterm-ghostty"})) != &Nerd {
		t.Fatal("ghostty does not get nerd icons")
	}
	if DetectIcons(env(map[string]string{"TERM": "xterm-ghostty", "NERD_FONTS": "0"})) != &Unicode {
		t.Fatal("NERD_FONTS=0 does not win")
	}
}

func TestPrinterAndTable(t *testing.T) {
	var out bytes.Buffer
	p := Printer{W: &out}
	p.Step("building %s", "x")
	p.Warn("careful")
	p.Done("ok")
	p.Error(errors.New("boom"))
	if want := "> building x\n! careful\n✔ ok\nerror: boom\n"; out.String() != want {
		t.Fatalf("printer output %q, want %q", out.String(), want)
	}

	out.Reset()
	st := NewStyle(true, nil)
	table := Table{Header: []string{"A", "Long header", "C"}, Rows: [][]string{{st.Paint("1", Green), "x", ""}, {"22", "y", "z"}}}
	if err := table.Render(&out, st); err != nil {
		t.Fatal(err)
	}
	if want := "A   Long header  C\n1   x\n22  y            z\n"; Strip(out.String()) != want {
		t.Fatalf("table:\n%q\nwant:\n%q", Strip(out.String()), want)
	}
	if err := (Table{Header: []string{"A"}, Rows: [][]string{{"1", "2"}}}).Render(&out, st); err == nil {
		t.Fatal("ragged table rendered")
	}
}

func TestGutter(t *testing.T) {
	var out bytes.Buffer
	g := Printer{W: &out}.Gutter(Notable)
	for _, chunk := range []string{"routine li", "ne\r\nwarning: x\n", "warning: x\n", "error: boom\n", "unit y failed\n", "tail"} {
		if _, err := g.Write([]byte(chunk)); err != nil {
			t.Fatal(err)
		}
	}
	if err := g.Close(); err != nil {
		t.Fatal(err)
	}
	if want := "│ ! x\n│ ✗ boom\n│ unit y failed\n"; out.String() != want {
		t.Fatalf("gutter = %q, want %q", out.String(), want)
	}
	out.Reset()
	if err := g.ShowHidden(); err != nil {
		t.Fatal(err)
	}
	if want := "│ output:\n│ routine line\n│ tail\n"; out.String() != want {
		t.Fatalf("hidden lines = %q, want %q", out.String(), want)
	}

	out.Reset()
	st := NewStyle(true, nil)
	g = Printer{W: &out, Style: st}.Gutter(Verbosity(Notable, true))
	if _, err := g.Write([]byte("plain\nwarning: careful\n")); err != nil {
		t.Fatal(err)
	}
	bar := st.Paint("│", Gray) + " "
	want := bar + st.Paint("plain", Faint) + "\n" + bar + st.Paint("!", Bold, Yellow) + " careful\n"
	if out.String() != want {
		t.Fatalf("verbose gutter = %q, want %q", out.String(), want)
	}
}

func TestRunIndentedShowsHiddenOutputOnFailure(t *testing.T) {
	var out bytes.Buffer
	c := Console{Streams: proc.Streams{Stderr: &out}}
	err := c.RunIndented(context.Background(), proc.Cmd{Argv: []string{"sh", "-c", "echo routine; echo warning: w; exit 3"}}, Notable)
	if code, ok := proc.ExitCode(err); !ok || code != 3 {
		t.Fatalf("err = %v", err)
	}
	if want := "│ ! w\n│ output:\n│ routine\n"; out.String() != want {
		t.Fatalf("output = %q, want %q", out.String(), want)
	}
	out.Reset()
	if err := c.RunIndented(context.Background(), proc.Cmd{Argv: []string{"sh", "-c", "echo routine"}}, Notable); err != nil || out.String() != "" {
		t.Fatalf("successful run printed %q, err %v", out.String(), err)
	}
}
