package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"

	"go.yaml.in/yaml/v3"
)

const (
	configFile     = "config.yaml"
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

type EnvVar struct {
	Name  string
	Value string
}

type Hook struct {
	Description string
	Exec        string
	Args        []string
	Env         []EnvVar
	SecretEnv   []EnvVar
}

type Config struct {
	Flake      string
	Platform   Platform
	Attr       string
	SSHKey     string
	PostSwitch []Hook
	Commands   []Command
}

func (c Config) FlakeRef() string { return "path:" + c.Flake }

func (c Config) SopsConfig() string { return filepath.Join(c.Flake, ".sops.yaml") }

func (c Config) SecretsDir() string { return filepath.Join(c.Flake, "secrets") }

func (c Config) SSHPublicKey() string { return c.SSHKey + ".pub" }

var (
	attrPattern    = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*$`)
	commandPattern = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)
	envNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
)

type fileChoice struct {
	Name        string `yaml:"name"`
	Description string `yaml:"description"`
}

type fileCommand struct {
	Name        string       `yaml:"name"`
	Description string       `yaml:"description"`
	Exec        string       `yaml:"exec"`
	Complete    []fileChoice `yaml:"complete"`
}

type fileHook struct {
	Description string            `yaml:"description"`
	Exec        string            `yaml:"exec"`
	Args        []string          `yaml:"args"`
	Env         map[string]string `yaml:"env"`
	SecretEnv   map[string]string `yaml:"secret_env"`
}

type file struct {
	Flake    string `yaml:"flake"`
	Platform string `yaml:"platform"`
	Attr     string `yaml:"attr"`
	SSHKey   string `yaml:"ssh_key"`
	Hooks    struct {
		PostSwitch []fileHook `yaml:"post_switch"`
	} `yaml:"hooks"`
	Commands []fileCommand `yaml:"commands"`
}

func ValidateAttr(attr string) error {
	if !attrPattern.MatchString(attr) {
		return fmt.Errorf("attr %q is not a Nix attribute name", attr)
	}
	return nil
}

func DefaultPath(getenv func(string) string) (string, error) {
	if p := getenv(EnvConfig); p != "" {
		return p, nil
	}
	if x := getenv("XDG_CONFIG_HOME"); x != "" {
		return filepath.Join(x, "hm", configFile), nil
	}
	home := getenv("HOME")
	if home == "" {
		return "", errors.New("locating the hm config: none of HM_CONFIG, XDG_CONFIG_HOME or HOME is set")
	}
	return filepath.Join(home, ".config", "hm", configFile), nil
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
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var f file
	if err := dec.Decode(&f); err != nil {
		return Config{}, err
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		return Config{}, errors.New("more than one YAML document")
	}

	platform, err := ParsePlatform(f.Platform)
	if err != nil {
		return Config{}, err
	}
	cfg := Config{
		Flake:    f.Flake,
		Platform: platform,
		Attr:     f.Attr,
		SSHKey:   f.SSHKey,
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
	if err := ValidateAttr(cfg.Attr); err != nil {
		return Config{}, err
	}
	if !filepath.IsAbs(cfg.SSHKey) {
		return Config{}, fmt.Errorf("ssh_key %q is not an absolute path", cfg.SSHKey)
	}
	if cfg.PostSwitch, err = parseHooks(f.Hooks.PostSwitch); err != nil {
		return Config{}, err
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

func parseHooks(in []fileHook) ([]Hook, error) {
	out := make([]Hook, len(in))
	for i, h := range in {
		if h.Description == "" {
			return nil, fmt.Errorf("post_switch hook %d has no description", i)
		}
		if !filepath.IsAbs(h.Exec) {
			return nil, fmt.Errorf("post_switch hook %q: exec %q is not an absolute path", h.Description, h.Exec)
		}
		env, err := envVars(h.Description, "env", h.Env)
		if err != nil {
			return nil, err
		}
		secretEnv, err := envVars(h.Description, "secret_env", h.SecretEnv)
		if err != nil {
			return nil, err
		}
		for _, v := range secretEnv {
			if v.Value == "" {
				return nil, fmt.Errorf("post_switch hook %q: secret_env %s names no secret", h.Description, v.Name)
			}
		}
		out[i] = Hook{Description: h.Description, Exec: h.Exec, Args: h.Args, Env: env, SecretEnv: secretEnv}
	}
	return out, nil
}

func envVars(hook, field string, in map[string]string) ([]EnvVar, error) {
	out := make([]EnvVar, 0, len(in))
	for _, name := range slices.Sorted(maps.Keys(in)) {
		if !envNamePattern.MatchString(name) {
			return nil, fmt.Errorf("post_switch hook %q: %s name %q is not an environment variable name", hook, field, name)
		}
		out = append(out, EnvVar{Name: name, Value: in[name]})
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
