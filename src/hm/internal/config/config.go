package config

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

const (
	EnvConfig      = "HM_CONFIG"
	EnvFlakeDir    = "HM_FLAKE_DIR"
	EnvNixOSConfig = "HM_NIXOS_CONFIG"
)

type Platform int

const (
	NixOS Platform = iota + 1
	Android
)

func (p Platform) String() string {
	switch p {
	case NixOS:
		return "nixos"
	case Android:
		return "android"
	}
	return fmt.Sprintf("Platform(%d)", int(p))
}

func ParsePlatform(s string) (Platform, error) {
	for _, p := range []Platform{NixOS, Android} {
		if p.String() == s {
			return p, nil
		}
	}
	return 0, fmt.Errorf("platform %q is not one of nixos, android", s)
}

type Choice struct {
	Name        string
	Description string
}

type Command struct {
	Name        string
	Description string
	Exec        string
	Complete    []Choice
}

type Config struct {
	Flake      string
	Platform   Platform
	Attr       string
	SSHKey     string
	PostSwitch []string
	Commands   []Command
}

func (c Config) FlakeRef() string { return "path:" + c.Flake }

func (c Config) SopsConfig() string { return filepath.Join(c.Flake, ".sops.yaml") }

func (c Config) SecretsDir() string { return filepath.Join(c.Flake, "secrets") }

func (c Config) SSHPublicKey() string { return c.SSHKey + ".pub" }

var (
	attrPattern    = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*$`)
	commandPattern = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)
)

type fileChoice struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type fileCommand struct {
	Name        string       `json:"name"`
	Description string       `json:"description"`
	Exec        string       `json:"exec"`
	Complete    []fileChoice `json:"complete"`
}

type file struct {
	Flake    string `json:"flake"`
	Platform string `json:"platform"`
	Attr     string `json:"attr"`
	SSHKey   string `json:"ssh_key"`
	Hooks    struct {
		PostSwitch []string `json:"post_switch"`
	} `json:"hooks"`
	Commands []fileCommand `json:"commands"`
}

func DefaultPath(getenv func(string) string) (string, error) {
	if p := getenv(EnvConfig); p != "" {
		return p, nil
	}
	if x := getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "hm", "config.json"), nil
	}
	home := getenv("HOME")
	if home == "" {
		return "", errors.New("locating the hm config: none of HM_CONFIG, XDG_CONFIG_HOME or HOME is set")
	}
	return filepath.Join(home, ".config", "hm", "config.json"), nil
}

func Load(path string, getenv func(string) string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("reading hm config: %w", err)
	}
	cfg, err := Parse(data, getenv)
	if err != nil {
		return Config{}, fmt.Errorf("parsing hm config %s: %w", path, err)
	}
	flake, err := resolveDir(cfg.Flake)
	if err != nil {
		return Config{}, err
	}
	cfg.Flake = flake
	return cfg, nil
}

func Parse(data []byte, getenv func(string) string) (Config, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var f file
	if err := dec.Decode(&f); err != nil {
		return Config{}, err
	}
	if dec.More() {
		return Config{}, errors.New("trailing data after the config object")
	}

	platform, err := ParsePlatform(f.Platform)
	if err != nil {
		return Config{}, err
	}
	cfg := Config{
		Flake:      f.Flake,
		Platform:   platform,
		Attr:       f.Attr,
		SSHKey:     f.SSHKey,
		PostSwitch: f.Hooks.PostSwitch,
	}
	if dir := getenv(EnvFlakeDir); dir != "" {
		cfg.Flake = dir
	}
	if attr := getenv(EnvNixOSConfig); attr != "" && platform == NixOS {
		cfg.Attr = attr
	}

	if cfg.Flake == "" {
		return Config{}, errors.New("flake is empty")
	}
	if !attrPattern.MatchString(cfg.Attr) {
		return Config{}, fmt.Errorf("attr %q is not a Nix attribute name", cfg.Attr)
	}
	if !filepath.IsAbs(cfg.SSHKey) {
		return Config{}, fmt.Errorf("ssh_key %q is not an absolute path", cfg.SSHKey)
	}
	for _, hook := range cfg.PostSwitch {
		if !filepath.IsAbs(hook) {
			return Config{}, fmt.Errorf("post_switch hook %q is not an absolute path", hook)
		}
	}
	commands, err := parseCommands(f.Commands)
	if err != nil {
		return Config{}, err
	}
	cfg.Commands = commands
	return cfg, nil
}

func parseCommands(in []fileCommand) ([]Command, error) {
	seen := make(map[string]bool, len(in))
	out := make([]Command, 0, len(in))
	for _, c := range in {
		if !commandPattern.MatchString(c.Name) {
			return nil, fmt.Errorf("command name %q must match %s", c.Name, commandPattern)
		}
		if seen[c.Name] {
			return nil, fmt.Errorf("command %q is declared twice", c.Name)
		}
		seen[c.Name] = true
		if !filepath.IsAbs(c.Exec) {
			return nil, fmt.Errorf("command %q: exec %q is not an absolute path", c.Name, c.Exec)
		}
		choices := make([]Choice, len(c.Complete))
		for i, ch := range c.Complete {
			if ch.Name == "" {
				return nil, fmt.Errorf("command %q: completion %d has an empty name", c.Name, i)
			}
			choices[i] = Choice(ch)
		}
		out = append(out, Command{Name: c.Name, Description: c.Description, Exec: c.Exec, Complete: choices})
	}
	return out, nil
}

func resolveDir(dir string) (string, error) {
	resolved, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", fmt.Errorf("resolving flake directory %s: %w", dir, err)
	}
	abs, err := filepath.Abs(resolved)
	if err != nil {
		return "", fmt.Errorf("resolving flake directory %s: %w", dir, err)
	}
	info, err := os.Stat(abs)
	if err != nil {
		return "", fmt.Errorf("resolving flake directory %s: %w", dir, err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("resolving flake directory %s: %s is not a directory", dir, abs)
	}
	return abs, nil
}
