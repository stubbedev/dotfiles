package config

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func env(vars map[string]string) func(string) string {
	return func(k string) string { return vars[k] }
}

const validConfig = `flake: /etc/nixos/dotfiles
platform: nixos
attr: desktop
ssh_key: /home/u/.ssh/id_ed25519
hooks:
  post_switch:
    - description: Pushing the closure
      exec: /nix/store/x-push/bin/push
      args: [push, --quiet, team/main]
      env:
        PUSH_URL: https://cache.example
        A_FIRST: "1"
      secret_env:
        PUSH_TOKEN: push-token
commands:
  - name: iso
    description: Build the ISO
    exec: /nix/store/x-iso/bin/nixos-iso
    complete:
      - name: build
        description: Build it
`

func TestParseValid(t *testing.T) {
	cfg, err := Parse([]byte(validConfig), env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Platform != NixOS || cfg.Attr != "desktop" || cfg.Flake != "/etc/nixos/dotfiles" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
	if cfg.SSHPublicKey() != "/home/u/.ssh/id_ed25519.pub" {
		t.Fatalf("SSHPublicKey = %q", cfg.SSHPublicKey())
	}
	if len(cfg.Commands) != 1 || cfg.Commands[0].Complete[0] != (Choice{Name: "build", Description: "Build it"}) {
		t.Fatalf("commands = %+v", cfg.Commands)
	}
	if cfg.FlakeRef() != "path:/etc/nixos/dotfiles" {
		t.Fatalf("FlakeRef = %q", cfg.FlakeRef())
	}
	want := Hook{
		Description: "Pushing the closure",
		Exec:        "/nix/store/x-push/bin/push",
		Args:        []string{"push", "--quiet", "team/main"},
		Env:         []EnvVar{{"A_FIRST", "1"}, {"PUSH_URL", "https://cache.example"}},
		SecretEnv:   []EnvVar{{"PUSH_TOKEN", "push-token"}},
	}
	if len(cfg.PostSwitch) != 1 || !reflect.DeepEqual(cfg.PostSwitch[0], want) {
		t.Fatalf("post_switch = %+v", cfg.PostSwitch)
	}
}

func TestParseEnvOverrides(t *testing.T) {
	cfg, err := Parse([]byte(validConfig), env(map[string]string{EnvFlakeDir: "/tmp/f", EnvNixOSConfig: "laptop"}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Flake != "/tmp/f" || cfg.Attr != "laptop" {
		t.Fatalf("overrides not applied: %+v", cfg)
	}

	android := strings.Replace(validConfig, "platform: nixos", "platform: android", 1)
	cfg, err = Parse([]byte(android), env(map[string]string{EnvNixOSConfig: "laptop"}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Attr != "desktop" {
		t.Fatalf("HM_NIXOS_CONFIG applied on Android: %q", cfg.Attr)
	}
}

func TestParseRejects(t *testing.T) {
	cases := map[string]string{
		"unknown platform":   strings.Replace(validConfig, "platform: nixos", "platform: linux", 1),
		"unknown field":      strings.Replace(validConfig, "attr:", "attribute:", 1),
		"unknown hook field": strings.Replace(validConfig, "      args:", "      argv:", 1),
		"bad attr":           strings.Replace(validConfig, "attr: desktop", "attr: a.b", 1),
		"relative ssh key":   strings.Replace(validConfig, "/home/u/.ssh/id_ed25519", "id_ed25519", 1),
		"relative hook":      strings.Replace(validConfig, "/nix/store/x-push/bin/push", "push", 1),
		"hook description":   strings.Replace(validConfig, "description: Pushing the closure", "description: \"\"", 1),
		"bad env name":       strings.Replace(validConfig, "PUSH_URL:", "PUSH-URL:", 1),
		"empty secret":       strings.Replace(validConfig, "PUSH_TOKEN: push-token", "PUSH_TOKEN: \"\"", 1),
		"relative exec":      strings.Replace(validConfig, "/nix/store/x-iso/bin/nixos-iso", "nixos-iso", 1),
		"bad command name":   strings.Replace(validConfig, "name: iso", "name: Iso", 1),
		"empty flake":        strings.Replace(validConfig, "flake: /etc/nixos/dotfiles", "flake: \"\"", 1),
		"second document":    validConfig + "---\nflake: /x\n",
		"duplicate command":  validConfig + "  - name: iso\n    exec: /bin/true\n",
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse([]byte(data), env(nil)); err == nil {
				t.Fatalf("accepted:\n%s", data)
			}
		})
	}
}

func TestLoadResolvesFlakeSymlink(t *testing.T) {
	dir := t.TempDir()
	real := filepath.Join(dir, "real")
	if err := os.Mkdir(real, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(strings.Replace(validConfig, "/etc/nixos/dotfiles", link, 1)), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path, env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Flake != real {
		t.Fatalf("Flake = %q, want %q", cfg.Flake, real)
	}

	if _, err := Load(path, env(map[string]string{EnvFlakeDir: filepath.Join(dir, "missing")})); err == nil {
		t.Fatal("Load accepted a missing flake directory")
	}
}

func TestDefaultPath(t *testing.T) {
	cases := []struct {
		vars map[string]string
		want string
	}{
		{map[string]string{EnvConfig: "/x.yaml", "HOME": "/h"}, "/x.yaml"},
		{map[string]string{"XDG_CONFIG_HOME": "/xdg", "HOME": "/h"}, "/xdg/hm/config.yaml"},
		{map[string]string{"HOME": "/h"}, "/h/.config/hm/config.yaml"},
	}
	for _, c := range cases {
		got, err := DefaultPath(env(c.vars))
		if err != nil || got != c.want {
			t.Fatalf("DefaultPath(%v) = %q, %v; want %q", c.vars, got, err, c.want)
		}
	}
	if _, err := DefaultPath(env(nil)); err == nil {
		t.Fatal("DefaultPath succeeded without HOME")
	}
}
