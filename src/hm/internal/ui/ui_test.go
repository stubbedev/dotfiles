package ui

import (
	"bytes"
	"errors"
	"os"
	"testing"
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
