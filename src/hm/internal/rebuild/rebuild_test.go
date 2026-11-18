package rebuild

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

func TestVerbNames(t *testing.T) {
	var names []string
	for _, v := range Verbs() {
		names = append(names, v.String())
	}
	want := []string{"switch", "boot", "test", "build", "dry-build", "dry-activate", "build-vm", "build-vm-with-bootloader"}
	if !slices.Equal(names, want) {
		t.Fatalf("verbs = %v, want %v", names, want)
	}
}

func TestVerbProperties(t *testing.T) {
	activating := map[Verb]bool{Switch: true, Boot: true, Test: true, DryActivate: true}
	for _, v := range Verbs() {
		if v.Activates() != activating[v] {
			t.Errorf("%s.Activates() = %v", v, v.Activates())
		}
		if NeedsRoot(config.Android, v) {
			t.Errorf("NeedsRoot(android, %s) = true", v)
		}
		if NeedsRoot(config.NixOS, v) != activating[v] {
			t.Errorf("NeedsRoot(nixos, %s) = %v", v, NeedsRoot(config.NixOS, v))
		}
	}
	if BuildVM.nixosAttr() != "config.system.build.vm" || Switch.nixosAttr() != "config.system.build.toplevel" {
		t.Fatal("unexpected attribute paths")
	}
}

func TestBuildSpecArgv(t *testing.T) {
	spec := buildSpec{installable: "path:/f#x", impure: true, extra: []string{"-L", "--show-trace"}}
	got := strings.Join(spec.argv(), " ")
	want := "nix --extra-experimental-features nix-command flakes build --log-format internal-json --print-out-paths --no-link --impure path:/f#x -L --show-trace"
	if got != want {
		t.Fatalf("argv = %q\nwant  %q", got, want)
	}
	if !spec.buildLogs() {
		t.Fatal("-L did not enable build logs")
	}
	linked := buildSpec{installable: "i", linkResult: true, dryRun: true}
	if got := strings.Join(linked.argv(), " "); strings.Contains(got, "--no-link") || !strings.Contains(got, "--dry-run") {
		t.Fatalf("argv = %q", got)
	}
}

func TestParseOutPath(t *testing.T) {
	if p, err := parseOutPath([]byte("/nix/store/abc-x\n")); err != nil || p != "/nix/store/abc-x" {
		t.Fatalf("parseOutPath = %q, %v", p, err)
	}
	for _, bad := range []string{"", "\n", "/a\n/b\n", "relative"} {
		if _, err := parseOutPath([]byte(bad)); err == nil {
			t.Errorf("parseOutPath(%q) succeeded", bad)
		}
	}
}

func TestParseSystemdVersion(t *testing.T) {
	v, err := parseSystemdVersion([]byte("systemd 258 (258.1)\n+PAM +AUDIT\n"))
	if err != nil || v != 258 {
		t.Fatalf("parseSystemdVersion = %d, %v", v, err)
	}
	if _, err := parseSystemdVersion([]byte("garbage")); err == nil {
		t.Fatal("parseSystemdVersion accepted garbage")
	}
}

func TestGenerationID(t *testing.T) {
	cases := map[string]int{"system-12-link": 12, "system-1-link": 1}
	for in, want := range cases {
		if got, ok := generationID("system", in); !ok || got != want {
			t.Errorf("generationID(%q) = %d, %v", in, got, ok)
		}
	}
	for _, bad := range []string{"system", "system-x-link", "system-0-link", "system-01-link", "other-1-link", "system-1"} {
		if _, ok := generationID("system", bad); ok {
			t.Errorf("generationID(%q) accepted", bad)
		}
	}
}

func makeGeneration(t *testing.T, dir string, id int, version, kernel string) {
	t.Helper()
	target := filepath.Join(dir, "store", strings.Repeat("a", 32)+"-gen"+string(rune('0'+id)))
	if err := os.MkdirAll(filepath.Join(target, "kernel-modules", "lib", "modules", kernel), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "nixos-version"), []byte(version+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "activate"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, generationPath(filepath.Join(dir, "profiles", "system"), id)); err != nil {
		t.Fatal(err)
	}
}

func generationsFixture(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "profiles"), 0o755); err != nil {
		t.Fatal(err)
	}
	makeGeneration(t, dir, 1, "26.05.1", "6.17.1")
	makeGeneration(t, dir, 2, "26.11.2", "6.18.63")
	profile := filepath.Join(dir, "profiles", "system")
	if err := os.Symlink("system-2-link", profile); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "profiles", "per-user"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return profile
}

func TestListGenerations(t *testing.T) {
	profile := generationsFixture(t)
	gens, err := ListGenerations(profile, "")
	if err != nil {
		t.Fatal(err)
	}
	if gens[0].NixOSVersion != "" {
		t.Fatalf("plain listing carries system info: %+v", gens[0])
	}
	if err := AddSystemInfo(profile, gens); err != nil {
		t.Fatal(err)
	}
	if len(gens) != 2 || gens[0].ID != 2 || !gens[0].Boot || !gens[0].Running || gens[1].Boot || gens[1].Running {
		t.Fatalf("generations = %+v", gens)
	}
	if gens[0].NixOSVersion != "26.11.2" || gens[0].Kernel != "6.18.63" || gens[0].Specialisations != nil {
		t.Fatalf("system info = %+v", gens[0])
	}
	if want, _ := filepath.EvalSymlinks(generationPath(profile, 2)); gens[0].Path != want {
		t.Fatalf("path = %q, want %q", gens[0].Path, want)
	}

	running := filepath.Join(t.TempDir(), "current-system")
	if err := os.Symlink(generationPath(profile, 1), running); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(gens[1].Path, "specialisation", "gaming"), 0o755); err != nil {
		t.Fatal(err)
	}
	gens, err = ListGenerations(profile, running)
	if err != nil {
		t.Fatal(err)
	}
	if err := AddSystemInfo(profile, gens); err != nil {
		t.Fatal(err)
	}
	if !gens[0].Boot || gens[0].Running || gens[1].Boot || !gens[1].Running {
		t.Fatalf("running and boot not told apart: %+v", gens)
	}
	if strings.Join(gens[1].Specialisations, ",") != "gaming" {
		t.Fatalf("specialisations = %v", gens[1].Specialisations)
	}
}

func TestWriteGenerations(t *testing.T) {
	date := time.Date(2026, 11, 17, 6, 30, 0, 0, time.UTC)
	gens := []Generation{
		{ID: 3, Date: date, NixOSVersion: "26.11.3", Kernel: "6.18.64", Boot: true, ClosureSize: 15 << 30},
		{ID: 2, Date: date, NixOSVersion: "26.11.2", Kernel: "6.18.63", Running: true, Specialisations: []string{"gaming", "work"}, ClosureSize: 14 << 30},
		{ID: 1, Date: date, NixOSVersion: "26.05.1", Kernel: "6.17.1", ClosureSize: 13 << 30},
	}
	var out bytes.Buffer
	if err := WriteGenerations(&out, ui.Style{}, gens, config.NixOS); err != nil {
		t.Fatal(err)
	}
	want := "Generation   Build date            NixOS version  Kernel   Specialisations  Closure size\n" +
		"3 (boot)     2026-11-17 06:30:00Z  26.11.3        6.18.64                   15.00 GiB\n" +
		"2 (running)  2026-11-17 06:30:00Z  26.11.2        6.18.63  gaming work      14.00 GiB\n" +
		"1            2026-11-17 06:30:00Z  26.05.1        6.17.1                    13.00 GiB\n"
	if out.String() != want {
		t.Fatalf("table:\n%s\nwant:\n%s", out.String(), want)
	}

	out.Reset()
	gens[0].Running = true
	if err := WriteGenerations(&out, ui.Style{}, gens[:1], config.Android); err != nil {
		t.Fatal(err)
	}
	if want := "Generation   Build date            Closure size\n3 (current)  2026-11-17 06:30:00Z  15.00 GiB\n"; out.String() != want {
		t.Fatalf("android table:\n%s\nwant:\n%s", out.String(), want)
	}

	out.Reset()
	if err := WriteGenerationsJSON(&out, gens[:1]); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"generation": 3`, `"boot": true`, `"running": true`, `"closureSize": 16106127360`} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("json lacks %s: %s", want, out.String())
		}
	}
}

func TestPreviousGeneration(t *testing.T) {
	profile := generationsFixture(t)
	prev, err := previousGeneration(profile)
	if err != nil {
		t.Fatal(err)
	}
	if prev != generationPath(profile, 1) {
		t.Fatalf("previousGeneration = %q", prev)
	}

	dir := filepath.Dir(filepath.Dir(profile))
	makeGeneration(t, dir, 4, "26.11.4", "6.18.64")
	if err := os.Remove(profile); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("system-4-link", profile); err != nil {
		t.Fatal(err)
	}
	if prev, err := previousGeneration(profile); err != nil || prev != generationPath(profile, 2) {
		t.Fatalf("previousGeneration across a gap = %q, %v", prev, err)
	}

	if err := os.Remove(profile); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("system-1-link", profile); err != nil {
		t.Fatal(err)
	}
	if _, err := previousGeneration(profile); err == nil {
		t.Fatal("previousGeneration of the first generation succeeded")
	}
}

func TestResolveGeneration(t *testing.T) {
	profile := generationsFixture(t)
	if got, err := ResolveGeneration(profile, "1"); err != nil || got != generationPath(profile, 1) {
		t.Fatalf("ResolveGeneration(1) = %q, %v", got, err)
	}
	if _, err := ResolveGeneration(profile, "9"); err == nil {
		t.Fatal("ResolveGeneration accepted a missing generation")
	}
	if got, err := ResolveGeneration(profile, "/nix/store/x"); err != nil || got != "/nix/store/x" {
		t.Fatalf("ResolveGeneration(path) = %q, %v", got, err)
	}
	old, current, err := DefaultDiffPair(profile)
	if err != nil || old != generationPath(profile, 1) || current != profile {
		t.Fatalf("DefaultDiffPair = %q, %q, %v", old, current, err)
	}
}

func TestDiffMode(t *testing.T) {
	for _, name := range DiffModeNames() {
		m, err := ParseDiffMode(name)
		if err != nil || m.String() != name {
			t.Fatalf("ParseDiffMode(%q) = %v, %v", name, m, err)
		}
	}
	if m, _ := ParseDiffMode("auto"); m != DiffAuto {
		t.Fatal("auto is not the zero value")
	}
	if _, err := ParseDiffMode("sometimes"); err == nil {
		t.Fatal("ParseDiffMode accepted sometimes")
	}
}

func TestConfirm(t *testing.T) {
	if err := confirm(Options{}, "q"); err != nil {
		t.Fatalf("confirm without --ask = %v", err)
	}
	var asked string
	yes := Options{Confirm: func(q string) (bool, error) { asked = q; return true, nil }}
	if err := confirm(yes, "Activate?"); err != nil || asked != "Activate?" {
		t.Fatalf("confirm yes = %v, asked %q", err, asked)
	}
	no := Options{Confirm: func(string) (bool, error) { return false, nil }}
	if err := confirm(no, "q"); !errors.Is(err, ErrDeclined) {
		t.Fatalf("confirm no = %v", err)
	}
}

func TestBuildTimes(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hm", buildTimesFile)
	if got, err := loadBuildTimes(path); err != nil || len(got) != 0 {
		t.Fatalf("missing cache = %v, %v", got, err)
	}
	merged := mergeBuildTimes(map[string]time.Duration{"linux": 10 * time.Minute, "kept": time.Second}, map[string]time.Duration{"linux": 20 * time.Minute, "new": 3 * time.Second, "trivial": 300 * time.Millisecond})
	if len(merged) != 3 || merged["linux"] != 15*time.Minute || merged["kept"] != time.Second || merged["new"] != 3*time.Second {
		t.Fatalf("merge = %v", merged)
	}
	if err := saveBuildTimes(path, merged); err != nil {
		t.Fatal(err)
	}
	loaded, err := loadBuildTimes(path)
	if err != nil || len(loaded) != 3 || loaded["linux"] != 15*time.Minute {
		t.Fatalf("round trip = %v, %v", loaded, err)
	}
	if err := os.WriteFile(path, []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadBuildTimes(path); err == nil || !strings.Contains(err.Error(), path) {
		t.Fatalf("corrupt cache err = %v", err)
	}
}

func TestParseRunRejectsInstallBootloaderOnBuild(t *testing.T) {
	if _, err := Run(t.Context(), Runtime{Config: config.Config{Platform: config.NixOS}}, Build, Options{InstallBootloader: true}); err == nil {
		t.Fatal("Run accepted --install-bootloader for build")
	}
}

func TestAndroidRejectsNixOSOnlyVerbs(t *testing.T) {
	for _, v := range []Verb{Boot, Test, DryBuild, DryActivate, BuildVM} {
		if _, err := Run(t.Context(), Runtime{Config: config.Config{Platform: config.Android}}, v, Options{}); err == nil || !strings.Contains(err.Error(), "unavailable on Android") {
			t.Errorf("Run(android, %s) = %v", v, err)
		}
	}
}

func TestDiffModes(t *testing.T) {
	current := t.TempDir()
	missing := filepath.Join(t.TempDir(), "never-built")
	run := func(mode DiffMode) (string, error) {
		var out bytes.Buffer
		c := ui.Console{Streams: proc.Streams{Stdout: &out, Stderr: &out}}
		err := diffClosures(t.Context(), c, current, missing, DiffOptions{Mode: mode})
		return out.String(), err
	}
	if out, err := run(DiffNever); err != nil || out != "" {
		t.Fatalf("never: %q, %v", out, err)
	}
	if out, err := run(DiffAuto); err != nil || !strings.Contains(out, "! skipping the closure diff") || !strings.Contains(out, "never-built") {
		t.Fatalf("auto: %q, %v", out, err)
	}
	if _, err := run(DiffAlways); err == nil || !strings.Contains(err.Error(), "never-built") {
		t.Fatalf("always: %v", err)
	}
	if err := diffClosures(t.Context(), ui.Console{}, filepath.Join(current, "absent"), missing, DiffOptions{Mode: DiffAlways}); err != nil {
		t.Fatalf("no current generation: %v", err)
	}
}
