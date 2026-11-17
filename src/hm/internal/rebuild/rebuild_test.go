package rebuild

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
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
	gens, err := ListGenerations(profile)
	if err != nil {
		t.Fatal(err)
	}
	if gens[0].NixOSVersion != "" {
		t.Fatalf("plain listing carries system info: %+v", gens[0])
	}
	if err := AddSystemInfo(profile, gens); err != nil {
		t.Fatal(err)
	}
	if len(gens) != 2 || gens[0].ID != 2 || !gens[0].Current || gens[1].Current {
		t.Fatalf("generations = %+v", gens)
	}
	if gens[0].NixOSVersion != "26.11.2" || gens[0].Kernel != "6.18.63" {
		t.Fatalf("system info = %+v", gens[0])
	}
}

func TestWriteGenerations(t *testing.T) {
	date := time.Date(2026, 11, 17, 6, 30, 0, 0, time.UTC)
	gens := []Generation{
		{ID: 2, Date: date, NixOSVersion: "26.11.2", Kernel: "6.18.63", Current: true},
		{ID: 1, Date: date, NixOSVersion: "26.05.1", Kernel: "6.17.1"},
	}
	var out bytes.Buffer
	if err := WriteGenerations(&out, gens, config.NixOS); err != nil {
		t.Fatal(err)
	}
	want := "Generation  Build-date            NixOS version  Kernel   Current\n" +
		"2           2026-11-17 06:30:00Z  26.11.2        6.18.63  *\n" +
		"1           2026-11-17 06:30:00Z  26.05.1        6.17.1   \n"
	if out.String() != want {
		t.Fatalf("table:\n%q\nwant:\n%q", out.String(), want)
	}

	out.Reset()
	if err := WriteGenerationsJSON(&out, gens[:1]); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), `"generation": 2`) || !strings.Contains(out.String(), `"current": true`) {
		t.Fatalf("json = %s", out.String())
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
