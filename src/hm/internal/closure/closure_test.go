package closure

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/stubbedev/dotfiles/src/hm/internal/storepath"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

func storePath(entry string) string {
	name, hash, ok := strings.Cut(entry, "@")
	if !ok {
		hash = "0"
	}
	return storepath.Dir + strings.Repeat(hash, 32) + "-" + name
}

func closureJSON(t *testing.T, top string, sizes map[string]int64, systemPackages ...string) []byte {
	t.Helper()
	infos := map[string]pathInfo{}
	for name, size := range sizes {
		infos[storePath(name)] = pathInfo{NarSize: size}
	}
	refs := make([]string, len(systemPackages))
	for i, name := range systemPackages {
		refs[i] = storePath(name)
	}
	infos[storePath("system-path")] = pathInfo{NarSize: 10, References: refs}
	infos[storePath(top)] = pathInfo{NarSize: 10, References: []string{storePath("system-path")}}
	data, err := json.Marshal(infos)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func mustParse(t *testing.T, top string, sizes map[string]int64, systemPackages ...string) Closure {
	t.Helper()
	c, err := Parse(storePath(top), closureJSON(t, top, sizes, systemPackages...))
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		old, new string
		want     ordering
	}{
		{"1.0", "1.1", newer},
		{"1.10", "1.9", older},
		{"1.0", "1.0", same},
		{"2.0rc1", "2.0", newer},
		{"2.0", "2.0-rc1", older},
		{"2.0", "2.0a", newer},
		{"2.0", "2.0.1", newer},
		{"5.2p37", "5.3p3", newer},
		{"0-unstable-2026-01-02", "0-unstable-2026-02-01", newer},
		{"abc1234", "def5678", unordered},
		{"010", "9", older},
	}
	for _, c := range cases {
		if got := compareVersions(Version(c.old), Version(c.new)); got != c.want {
			t.Errorf("compareVersions(%q, %q) = %d, want %d", c.old, c.new, got, c.want)
		}
	}
}

func TestParseRejectsForeignPaths(t *testing.T) {
	if _, err := Parse(storePath("x"), []byte(`{"/tmp/x":{"narSize":1}}`)); err == nil {
		t.Fatal("Parse accepted a closure without its root")
	}
	if _, err := Parse("/tmp/x", []byte(`{"/tmp/x":{"narSize":1}}`)); err == nil {
		t.Fatal("Parse accepted a non-store path")
	}
	if _, err := Parse(storePath("x"), []byte(`[`)); err == nil {
		t.Fatal("Parse accepted malformed JSON")
	}
}

func TestDiffAndRender(t *testing.T) {
	oldC := mustParse(t, "nixos-system-desktop-26.11@1", map[string]int64{
		"firefox-140.0":       100 << 20,
		"bash-5.2p37":         1 << 20,
		"zlib-1.3":            100,
		"gone-1.0":            1000,
		"kept-1.0":            10,
		"source@1":            5 << 20,
		"tiny@1":              10,
		"python3-3.12.1":      1 << 20,
		"python3-3.12.1-dev":  1 << 20,
		"perl-5.40.0-env-1.0": 1,
	}, "firefox-140.0", "gone-1.0")
	newC := mustParse(t, "nixos-system-desktop-26.11@2", map[string]int64{
		"firefox-141.0":       101 << 20,
		"bash-5.2p36":         1 << 20,
		"zlib-1.3":            100,
		"new-2.0":             1000,
		"kept-1.0":            10,
		"source@2":            7 << 20,
		"tiny@2":              20,
		"python3-3.12.1":      1 << 20,
		"python3-3.12.1-dev":  1 << 20,
		"python3-3.13.0":      1 << 20,
		"perl-5.40.0-env-1.0": 1,
	}, "firefox-141.0", "new-2.0")
	report := Diff(oldC, newC)
	if report.PathsOld != 12 || report.PathsNew != 13 || report.PathsAdded != 7 || report.PathsRemoved != 6 {
		t.Fatalf("path stats = %+v", report)
	}
	var out bytes.Buffer
	if err := Render(&out, ui.Style{}, report, RenderOptions{FullFlag: "--full"}); err != nil {
		t.Fatal(err)
	}
	want := `
CHANGED (4)
[D.] bash    5.2p37 -> 5.2p36
[U*] firefox 140.0 -> 141.0, +1.00 MiB
[C.] python3 <unchanged> -> 3.13.0, <unchanged>, +1.00 MiB
[C.] source  +2.00 MiB

ADDED (1)
[A+] new     2.0

REMOVED (1)
[R-] gone    1.0

PATHS: 12 -> 13 (+7, -6)
SIZE: 108.00 MiB -> 112.00 MiB (+4.00 MiB)

NOTE: 1 hidden (size-only changes under 1.00 MiB, --full to show)
`
	if out.String() != want {
		t.Fatalf("render:\n%s\nwant:\n%s", out.String(), want)
	}

	out.Reset()
	if err := Render(&out, ui.NewStyle(true, nil), report, RenderOptions{FullFlag: "--full"}); err != nil {
		t.Fatal(err)
	}
	if ui.Strip(out.String()) != want {
		t.Fatalf("colored render differs from plain once stripped:\n%s", ui.Strip(out.String()))
	}
	out.Reset()
	if err := Render(&out, ui.Style{}, report, RenderOptions{Full: true, FullFlag: "--full"}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "[C.] tiny\n") {
		t.Fatalf("--full does not show size-only changes:\n%s", out.String())
	}
	if strings.Contains(out.String(), "NOTE") {
		t.Fatalf("--full still notes hidden packages:\n%s", out.String())
	}
	out.Reset()
	if err := Render(&out, ui.NewStyle(true, nil), report, RenderOptions{FullFlag: "--full"}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "\x1b[33m5\x1b[0m.\x1b[33m2p3\x1b[0m\x1b[31m7\x1b[0m") {
		t.Fatalf("version diff not highlighted per character:\n%q", out.String())
	}
}
