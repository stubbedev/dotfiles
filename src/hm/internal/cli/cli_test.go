package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"
	"go.yaml.in/yaml/v3"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

var sopsFixture = mustAbs(filepath.Join("..", "sops", "testdata", "sops.yaml"))

func mustAbs(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		panic(err)
	}
	return abs
}

type harness struct {
	t     *testing.T
	dir   string
	flake string
	home  string
}

func requireTools(t *testing.T, names ...string) {
	t.Helper()
	for _, name := range names {
		if _, err := exec.LookPath(name); err != nil {
			t.Fatalf("%s is required on PATH for this test: %v", name, err)
		}
	}
}

func newHarness(t *testing.T, commands ...map[string]any) *harness {
	t.Helper()
	dir := t.TempDir()
	h := &harness{t: t, dir: dir, flake: filepath.Join(dir, "flake"), home: filepath.Join(dir, "home")}
	for _, d := range []string{filepath.Join(h.flake, "secrets"), filepath.Join(h.home, ".ssh"), filepath.Join(dir, "elsewhere")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	sopsYAML, err := os.ReadFile(sopsFixture)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(h.flake, ".sops.yaml"), sopsYAML, 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "flake-link")
	if err := os.Symlink(h.flake, link); err != nil {
		t.Fatal(err)
	}
	if commands == nil {
		commands = []map[string]any{}
	}
	cfg, err := json.Marshal(map[string]any{
		"flake":    "/nonexistent",
		"platform": "nixos",
		"attr":     "desktop",
		"ssh_key":  filepath.Join(h.home, ".ssh", "id_ed25519"),
		"commands": commands,
	})
	if err != nil {
		t.Fatal(err)
	}
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, cfg, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", h.home)
	t.Setenv("HM_CONFIG", cfgPath)
	t.Setenv("HM_FLAKE_DIR", link)
	t.Setenv("SOPS_AGE_KEY_FILE", "")
	t.Chdir(filepath.Join(dir, "elsewhere"))
	return h
}

func (h *harness) run(stdin string, args ...string) (string, string, int) {
	h.t.Helper()
	var out, errOut bytes.Buffer
	app := New(proc.Streams{Stdin: strings.NewReader(stdin), Stdout: &out, Stderr: &errOut}, Terminal{})
	code := app.Run(context.Background(), args)
	return out.String(), errOut.String(), code
}

func (h *harness) mustRun(stdin string, args ...string) string {
	h.t.Helper()
	out, errOut, code := h.run(stdin, args...)
	if code != 0 {
		h.t.Fatalf("hm %v exited %d\nstdout: %s\nstderr: %s", args, code, out, errOut)
	}
	return out
}

func (h *harness) recipients() ([]string, map[string]string) {
	h.t.Helper()
	data, err := os.ReadFile(filepath.Join(h.flake, ".sops.yaml"))
	if err != nil {
		h.t.Fatal(err)
	}
	var doc struct {
		Rules []struct {
			Groups []struct {
				Age yaml.Node `yaml:"age"`
			} `yaml:"key_groups"`
		} `yaml:"creation_rules"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		h.t.Fatal(err)
	}
	var keys []string
	comments := map[string]string{}
	for _, r := range doc.Rules {
		for _, g := range r.Groups {
			for _, n := range g.Age.Content {
				keys = append(keys, n.Value)
				comments[n.Value] = strings.TrimSpace(strings.TrimPrefix(n.LineComment, "#"))
			}
		}
	}
	return keys, comments
}

func command(t *testing.T, name string, args ...string) string {
	t.Helper()
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		t.Fatalf("%s %v: %v", name, args, err)
	}
	return strings.TrimSpace(string(out))
}

func TestHelp(t *testing.T) {
	h := newHarness(t)
	out := h.mustRun("", "help")
	for _, want := range []string{"Usage:", "Rebuild:", "Maintenance:", "switch", "dry-activate", "trust", "secret", "HM_FLAKE_DIR"} {
		if !strings.Contains(out, want) {
			t.Errorf("help lacks %q:\n%s", want, out)
		}
	}
	if out, _, code := h.run("", "switch", "--help"); code != 0 || !strings.Contains(out, "--install-bootloader") || !strings.Contains(out, "--show-trace") {
		t.Errorf("switch --help exited %d:\n%s", code, out)
	}
	if out, _, code := h.run("", "build", "--help"); code != 0 || strings.Contains(out, "--install-bootloader") {
		t.Errorf("build --help offers --install-bootloader:\n%s", out)
	}
	if strings.Contains(out, "\x1b[") {
		t.Errorf("help is colored without a color terminal:\n%q", out)
	}
}

func TestColoredOutput(t *testing.T) {
	h := newHarness(t)
	colored := Terminal{Stdout: ui.NewStyle(true, nil), Stderr: ui.NewStyle(true, nil)}
	run := func(args ...string) (string, string, int) {
		var out, errOut bytes.Buffer
		code := New(proc.Streams{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut}, colored).Run(context.Background(), args)
		return out.String(), errOut.String(), code
	}

	plain := h.mustRun("", "switch", "--help")
	out, _, code := run("switch", "--help")
	if code != 0 || ui.Strip(out) != plain {
		t.Fatalf("colored help differs from plain once stripped (exit %d):\n%s", code, ui.Strip(out))
	}
	for _, want := range []string{
		"\x1b[1;33mUsage:\x1b[0m",
		"\x1b[1;33mGlobal Flags:\x1b[0m",
		"\x1b[1;31m-L, --print-build-logs\x1b[0m",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("colored switch --help lacks %q:\n%q", want, out)
		}
	}
	if out, _, _ := run("help"); !strings.Contains(out, "\x1b[1;32mswitch ") || !strings.Contains(out, "\x1b[1;33mEnvironment:\x1b[0m") {
		t.Errorf("colored help does not highlight commands and headings:\n%q", out)
	}

	_, errOut, code := run()
	if code != 2 || !strings.Contains(errOut, "\x1b[1;33mUsage:\x1b[0m") || !strings.Contains(errOut, "\x1b[1;31merror:\x1b[0m no command given") {
		t.Fatalf("bare hm exited %d with stderr:\n%q", code, errOut)
	}
}

func TestUsageErrorsExitTwo(t *testing.T) {
	h := newHarness(t)
	cases := [][]string{
		{},
		{"frobnicate"},
		{"rollback", "extra"},
		{"secret"},
		{"secret", "shred", "x"},
		{"secret", "set"},
		{"generations", "--bogus"},
		{"switch", "--bogus"},
		{"switch", "extra"},
		{"build", "--install-bootloader"},
		{"switch", "--option", "noequals"},
		{"rollback", "x"},
		{"rollback", "0"},
		{"rollback", "1", "2"},
		{"--attr", "a.b", "generations"},
		{"gc", "stray"},
	}
	for _, args := range cases {
		if _, errOut, code := h.run("", args...); code != 2 {
			t.Errorf("hm %v exited %d, want 2; stderr: %s", args, code, errOut)
		}
	}
}

func TestMissingConfig(t *testing.T) {
	newHarness(t)
	t.Setenv("HM_CONFIG", filepath.Join(t.TempDir(), "missing.json"))
	var out, errOut bytes.Buffer
	code := New(proc.Streams{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut}, Terminal{}).Run(context.Background(), []string{"switch"})
	if code != 1 || !strings.Contains(errOut.String(), "missing.json") {
		t.Fatalf("exit %d, stderr %q", code, errOut.String())
	}
	code = New(proc.Streams{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut}, Terminal{}).Run(context.Background(), []string{"completion", "zsh"})
	if code != 0 || !strings.HasPrefix(out.String(), "#compdef hm") {
		t.Fatalf("completion without a config: exit %d, output %q", code, out.String())
	}
}

func TestExternalCommands(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "hm-echo")
	if err := os.WriteFile(script, []byte("#!/bin/sh\necho \"args:$*\"\nexit \"${EXIT:-0}\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, map[string]any{
		"name": "echo", "description": "Echo things", "exec": script,
		"complete": []map[string]string{{"name": "loud", "description": "Shout"}},
	})
	if out := h.mustRun("", "echo", "a", "--flag"); out != "args:a --flag\n" {
		t.Fatalf("external output %q", out)
	}
	if out := h.mustRun("", "help"); !strings.Contains(out, "Extra:") || !strings.Contains(out, "Echo things") {
		t.Fatalf("help lacks the external command:\n%s", out)
	}
	if out := h.mustRun("", "__complete", "echo", ""); !strings.Contains(out, "loud\tShout") {
		t.Fatalf("completion lacks the external choices:\n%s", out)
	}
	t.Setenv("EXIT", "7")
	if _, errOut, code := h.run("", "echo"); code != 7 || strings.Contains(errOut, "hm:") {
		t.Fatalf("external failure: exit %d, stderr %q", code, errOut)
	}
}

func TestExternalCollision(t *testing.T) {
	h := newHarness(t, map[string]any{"name": "switch", "description": "", "exec": "/bin/true"})
	if _, errOut, code := h.run("", "help"); code != 1 || !strings.Contains(errOut, "collides") {
		t.Fatalf("collision: exit %d, stderr %q", code, errOut)
	}
}

func TestSecretCompletion(t *testing.T) {
	h := newHarness(t)
	for _, name := range []string{"github-token", ".hidden"} {
		if err := os.WriteFile(filepath.Join(h.flake, "secrets", name), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	out := h.mustRun("", "__complete", "secret", "edit", "")
	if !strings.Contains(out, "github-token") || strings.Contains(out, ".hidden") {
		t.Fatalf("secret completion:\n%s", out)
	}
}

func TestTrustAndSecrets(t *testing.T) {
	requireTools(t, "sops", "age", "age-keygen", "ssh-to-age", "ssh-keygen")
	h := newHarness(t)

	firstKey := filepath.Join(h.dir, "first.key")
	secondKey := filepath.Join(h.dir, "second.key")
	command(t, "age-keygen", "-o", firstKey)
	command(t, "age-keygen", "-o", secondKey)
	first := command(t, "age-keygen", "-y", firstKey)
	second := command(t, "age-keygen", "-y", secondKey)
	before, _ := h.recipients()

	out := h.mustRun("", "trust", "first", first)
	keys, comments := h.recipients()
	if strings.Join(keys, " ") != strings.Join(append(before, first), " ") {
		t.Fatalf("trust did not append %s: %v", first, keys)
	}
	if comments[first] != "first" {
		t.Fatalf("trust labelled %s as %q", first, comments[first])
	}
	if !strings.Contains(out, `git -C "`+h.flake+`" diff`) {
		t.Fatalf("HM_FLAKE_DIR not resolved to %s:\n%s", h.flake, out)
	}
	if !strings.Contains(out, "\n✔ Trusted first across 0 secret file(s)\n  Review:") {
		t.Fatalf("trust summary misformatted:\n%s", out)
	}

	snapshot, _ := os.ReadFile(filepath.Join(h.flake, ".sops.yaml"))
	if out := h.mustRun("", "trust", "first", first); !strings.Contains(out, "already present") {
		t.Fatalf("re-trust not a no-op:\n%s", out)
	}
	if now, _ := os.ReadFile(filepath.Join(h.flake, ".sops.yaml")); !bytes.Equal(now, snapshot) {
		t.Fatal("re-trusting changed .sops.yaml")
	}

	h.mustRun("hunter2\n\n", "secret", "set", "token")
	t.Setenv("SOPS_AGE_KEY_FILE", firstKey)
	out = h.mustRun("", "trust", "second", second)
	if !strings.Contains(out, "Re-wrapping token") || !strings.Contains(out, "Trusted second across 1 secret file(s)") {
		t.Fatalf("trust did not re-wrap token:\n%s", out)
	}
	keys, _ = h.recipients()
	if strings.Join(keys, " ") != strings.Join(append(before, first, second), " ") {
		t.Fatalf("trust did not append %s: %v", second, keys)
	}
	t.Setenv("SOPS_AGE_KEY_FILE", secondKey)
	plain := command(t, "sops", "--decrypt", "--input-type", "binary", "--output-type", "binary", filepath.Join(h.flake, "secrets", "token"))
	if plain != "hunter2" {
		t.Fatalf("secrets/token decrypts to %q for %s", plain, second)
	}

	if _, _, code := h.run("a\x00b", "secret", "set", "nul"); code != 1 {
		t.Fatalf("NUL value exited %d, want 1", code)
	}
	if _, err := os.Stat(filepath.Join(h.flake, "secrets", "nul")); !os.IsNotExist(err) {
		t.Fatal("a value with a NUL byte was written")
	}
	for _, name := range []string{"../escape", "/etc/escape", ".hidden", "sub/dir", ""} {
		if _, _, code := h.run("x", "secret", "set", name); code != 2 {
			t.Errorf("secret set %q exited %d, want 2", name, code)
		}
	}
	if _, err := os.Stat(filepath.Join(h.flake, "escape")); !os.IsNotExist(err) {
		t.Fatal("secret set ../escape wrote outside secrets/")
	}
	if entries, _ := os.ReadDir(filepath.Join(h.flake, "secrets")); len(entries) != 1 {
		t.Fatalf("secrets/ holds %v, want only token", entries)
	}

	if out := h.mustRun("", "secret", "rotate", "token"); !strings.Contains(out, "Re-rolled data key for token") {
		t.Fatalf("rotate output:\n%s", out)
	}
	if plain := command(t, "sops", "--decrypt", "--input-type", "binary", "--output-type", "binary", filepath.Join(h.flake, "secrets", "token")); plain != "hunter2" {
		t.Fatalf("rotated token decrypts to %q", plain)
	}
	if _, _, code := h.run("", "secret", "rotate", "absent"); code != 1 {
		t.Fatalf("rotating a missing secret exited %d, want 1", code)
	}

	if _, _, code := h.run("", "trust", "bad name", second); code != 2 {
		t.Fatalf("invalid trust name exited %d, want 2", code)
	}
	if _, _, code := h.run("", "trust", "x", "not-a-key"); code != 2 {
		t.Fatalf("invalid pubkey exited %d, want 2", code)
	}
}

func TestWhoamiPipesIntoTrust(t *testing.T) {
	requireTools(t, "sops", "age", "ssh-to-age", "ssh-keygen")
	h := newHarness(t)
	command(t, "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", filepath.Join(h.home, ".ssh", "id_ed25519"))
	own := command(t, "sh", "-c", "ssh-to-age < \"$1\"", "sh", filepath.Join(h.home, ".ssh", "id_ed25519.pub"))
	host, err := shortHostname()
	if err != nil {
		t.Fatal(err)
	}

	whoami := h.mustRun("", "whoami")
	if whoami != host+" "+own+"\n" {
		t.Fatalf("whoami printed %q", whoami)
	}
	h.mustRun(whoami, "trust")
	if _, comments := h.recipients(); comments[own] != host {
		t.Fatalf("piped trust labelled %s as %q, want %q", own, comments[own], host)
	}

	h2 := newHarness(t)
	command(t, "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", filepath.Join(h2.home, ".ssh", "id_ed25519"))
	own2 := command(t, "sh", "-c", "ssh-to-age < \"$1\"", "sh", filepath.Join(h2.home, ".ssh", "id_ed25519.pub"))
	h2.mustRun("", "trust", own2)
	if _, comments := h2.recipients(); comments[own2] != host {
		t.Fatalf("own key auto-named %q, want %q", comments[own2], host)
	}
	h2.mustRun("", "trust", own)
	if _, comments := h2.recipients(); comments[own] != own[len(own)-8:] {
		t.Fatalf("foreign key auto-named %q", comments[own])
	}
}

func parseRebuildFlags(t *testing.T, terminal Terminal, v rebuild.Verb, args ...string) (rebuild.Options, error) {
	t.Helper()
	app := New(proc.Streams{Stdin: strings.NewReader("y\n"), Stdout: io.Discard, Stderr: io.Discard}, terminal)
	var got rebuild.Options
	cmd := &cobra.Command{Use: v.String(), SilenceErrors: true, SilenceUsage: true}
	flags, err := addRebuildFlags(cmd, v)
	if err != nil {
		t.Fatal(err)
	}
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		var err error
		got, err = app.rebuildOptions(flags, cmd, args)
		return err
	}
	cmd.SetArgs(args)
	return got, cmd.Execute()
}

func TestNixFlagsTranslate(t *testing.T) {
	got, err := parseRebuildFlags(t, Terminal{}, rebuild.Switch, "-L", "--show-trace", "-vv", "-j", "auto", "--cores", "4", "--option", "substitute=false", "--override-input", "nixpkgs=path:/x", "--install-bootloader", "--diff", "never", "--diff-full", "--", "--repair", "x")
	if err != nil {
		t.Fatal(err)
	}
	want := "--show-trace --print-build-logs -v -v --max-jobs auto --cores 4 --option substitute false --override-input nixpkgs path:/x --repair x"
	if strings.Join(got.Extra, " ") != want || !got.InstallBootloader || got.Confirm != nil {
		t.Fatalf("options = %+v\nwant extra %q", got, want)
	}
	if got.Diff != (rebuild.DiffOptions{Mode: rebuild.DiffNever, Full: true}) {
		t.Fatalf("diff options = %+v", got.Diff)
	}
	if got, err := parseRebuildFlags(t, Terminal{}, rebuild.Build); err != nil || got.Diff.Mode != rebuild.DiffAuto {
		t.Fatalf("default diff mode = %v, %v", got.Diff.Mode, err)
	}
	if _, err := parseRebuildFlags(t, Terminal{}, rebuild.Switch, "--diff", "sometimes"); err == nil {
		t.Fatal("--diff sometimes accepted")
	}
	if _, err := parseRebuildFlags(t, Terminal{}, rebuild.DryBuild, "--diff", "never"); err == nil {
		t.Fatal("dry-build offers --diff although it never diffs")
	}
	if _, err := parseRebuildFlags(t, Terminal{}, rebuild.Build, "--ask"); err == nil {
		t.Fatal("build offers --ask although it never activates")
	}
	if _, err := parseRebuildFlags(t, Terminal{}, rebuild.Switch, "--ask"); !usage.Is(err) {
		t.Fatalf("--ask without a terminal = %v, want a usage error", err)
	}
	asked, err := parseRebuildFlags(t, Terminal{StdinTTY: true}, rebuild.Switch, "--ask")
	if err != nil || asked.Confirm == nil {
		t.Fatalf("--ask on a terminal = %+v, %v", asked, err)
	}
	if ok, err := asked.Confirm("Activate?"); err != nil || !ok {
		t.Fatalf("confirm read y as %v, %v", ok, err)
	}
}

func TestConfirmAnswers(t *testing.T) {
	for answer, want := range map[string]bool{"y\n": true, "YES\n": true, "\n": false, "n\n": false, "": false, "yep\n": false} {
		var errOut bytes.Buffer
		app := New(proc.Streams{Stdin: strings.NewReader(answer), Stdout: io.Discard, Stderr: &errOut}, Terminal{StdinTTY: true})
		got, err := app.confirm("Activate?")
		if err != nil || got != want {
			t.Errorf("answer %q = %v, %v; want %v", answer, got, err, want)
		}
		if errOut.String() != "? Activate? [y/N] " {
			t.Errorf("prompt = %q", errOut.String())
		}
	}
}

func TestCompletion(t *testing.T) {
	h := newHarness(t)
	if out := h.mustRun("", "__complete", "switch", "--sh"); !strings.Contains(out, "--show-trace") {
		t.Fatalf("flag completion:\n%s", out)
	}
	if out := h.mustRun("", "__complete", "gc", "--d"); !strings.Contains(out, "--delete-older-than") {
		t.Fatalf("gc flag completion:\n%s", out)
	}
	for _, shell := range []string{"zsh", "bash", "fish"} {
		if out := h.mustRun("", "completion", shell); !strings.Contains(out, "__complete") {
			t.Errorf("%s completion script does not call back into hm", shell)
		}
	}

	profiles := filepath.Join(t.TempDir(), "profiles")
	if err := os.MkdirAll(profiles, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"1", "2", "3"} {
		if err := os.Symlink(h.dir, filepath.Join(profiles, "system-"+id+"-link")); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink("system-3-link", filepath.Join(profiles, "system")); err != nil {
		t.Fatal(err)
	}
	var out, errOut bytes.Buffer
	app := New(proc.Streams{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut}, Terminal{})
	app.profile = func(config.Platform) string { return filepath.Join(profiles, "system") }
	if code := app.Run(context.Background(), []string{"__complete", "rollback", ""}); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	lines := strings.Split(out.String(), "\n")
	if !strings.HasPrefix(lines[0], "2\t") || !strings.HasPrefix(lines[1], "1\t") || strings.Contains(out.String(), "3\t") {
		t.Fatalf("rollback completion:\n%s", out.String())
	}

	out.Reset()
	if code := app.Run(context.Background(), []string{"__complete", "diff", "1", ""}); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if lines := strings.Split(out.String(), "\n"); !strings.HasPrefix(lines[0], "3\t") || !strings.HasPrefix(lines[2], "1\t") {
		t.Fatalf("diff completion:\n%s", out.String())
	}
	out.Reset()
	if code := app.Run(context.Background(), []string{"__complete", "diff", "1", "2", ""}); code != 0 || strings.Contains(out.String(), "\t") {
		t.Fatalf("diff completes a third argument:\n%s", out.String())
	}
	out.Reset()
	if code := app.Run(context.Background(), []string{"__complete", "switch", "--diff", ""}); code != 0 || !strings.HasPrefix(out.String(), "auto\nalways\nnever\n") {
		t.Fatalf("--diff completion:\n%s", out.String())
	}

	out.Reset()
	errOut.Reset()
	if code := app.Run(context.Background(), []string{"diff", "9"}); code != 1 || !strings.Contains(errOut.String(), "generation 9") {
		t.Fatalf("diff of a missing generation exited %d: %s", code, errOut.String())
	}
	if code := app.Run(context.Background(), []string{"diff", "1", "2", "3"}); code != 2 {
		t.Fatalf("diff with three arguments exited %d", code)
	}
}
