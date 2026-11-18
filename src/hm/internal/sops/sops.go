package sops

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/stubbedev/dotfiles/src/hm/internal/atomicfile"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

const (
	autoNameSuffix = 8
	secretPerm     = 0o644
)

var (
	secretNamePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
	trustNamePattern  = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)
	binaryMode        = []string{"--input-type", "binary", "--output-type", "binary"}
)

type Store struct {
	Flake   string
	Console ui.Console
}

func (s Store) configPath() string { return filepath.Join(s.Flake, ".sops.yaml") }

func (s Store) secretsDir() string { return filepath.Join(s.Flake, "secrets") }

func (s Store) sops(args ...string) proc.Cmd {
	return s.Console.Cmd(append([]string{"sops", "--config", s.configPath()}, args...)...)
}

func ValidateSecretName(name string) error {
	if !secretNamePattern.MatchString(name) {
		return usage.Errorf("secret name %q must match %s (a file directly under secrets/)", name, secretNamePattern)
	}
	return nil
}

func (s Store) ResolveSecret(name string) (string, error) {
	if err := ValidateSecretName(name); err != nil {
		return "", err
	}
	path := filepath.Join(s.secretsDir(), name)
	if _, err := os.Lstat(path); err == nil {
		return path, nil
	} else if !errors.Is(err, fs.ErrNotExist) {
		return "", fmt.Errorf("looking up secret %s: %w", name, err)
	}
	hits, err := filepath.Glob(filepath.Join(s.secretsDir(), name+".*"))
	if err != nil {
		return "", fmt.Errorf("looking up secret %s: %w", name, err)
	}
	switch len(hits) {
	case 0:
		return path, nil
	case 1:
		return hits[0], nil
	}
	names := make([]string, len(hits))
	for i, h := range hits {
		names[i] = filepath.Base(h)
	}
	return "", usage.Errorf("secret %q is ambiguous: %s", name, strings.Join(names, " "))
}

func (s Store) SecretNames() ([]string, error) {
	entries, err := os.ReadDir(s.secretsDir())
	if err != nil {
		return nil, fmt.Errorf("listing secrets: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.Type().IsRegular() && !strings.HasPrefix(e.Name(), ".") {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

func (s Store) Edit(ctx context.Context, path string) error {
	return proc.Run(ctx, s.sops(append(slices.Clone(binaryMode), path)...))
}

func (s Store) Set(ctx context.Context, path string, value []byte) error {
	cmd := s.sops(append([]string{"--encrypt"}, append(slices.Clone(binaryMode), "--filename-override", path, "/dev/stdin")...)...)
	cmd.Stdin = bytes.NewReader(value)
	return atomicfile.Replace(path, secretPerm, func(w io.Writer) error {
		cmd.Stdout = w
		if err := proc.Run(ctx, cmd); err != nil {
			return fmt.Errorf("encrypting %s: %w", path, err)
		}
		return nil
	})
}

func (s Store) Rotate(ctx context.Context, path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("rotating %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("rotating %s: not a regular file", path)
	}
	return proc.Run(ctx, s.sops(append([]string{"--rotate", "-i"}, append(slices.Clone(binaryMode), path)...)...))
}

func ParsePipedValue(data []byte) ([]byte, error) {
	if bytes.IndexByte(data, 0) >= 0 {
		return nil, errors.New("value contains a NUL byte")
	}
	value := bytes.TrimRight(data, "\n")
	if len(value) == 0 {
		return nil, errors.New("refusing to write an empty value")
	}
	return value, nil
}

func AgePubkey(ctx context.Context, s proc.Streams, sshPublicKey string) (string, error) {
	f, err := os.Open(sshPublicKey)
	if err != nil {
		return "", fmt.Errorf("deriving an age pubkey: %w", err)
	}
	defer f.Close()
	out, err := proc.Output(ctx, proc.Cmd{Argv: []string{"ssh-to-age"}, Stdin: f, Stderr: s.Stderr})
	if err != nil {
		return "", fmt.Errorf("deriving an age pubkey from %s: %w", sshPublicKey, err)
	}
	return strings.TrimSpace(string(out)), nil
}

type TrustRequest struct {
	Name   string
	Pubkey string
}

func ParseTrustArgs(args []string, stdin io.Reader, stdinTTY bool) (TrustRequest, error) {
	switch len(args) {
	case 2:
		return TrustRequest{Name: args[0], Pubkey: args[1]}, nil
	case 1:
		return TrustRequest{Pubkey: args[0]}, nil
	case 0:
		if stdinTTY {
			return TrustRequest{}, usage.Errorf("trust needs a pubkey: hm trust [name] <pubkey>, or pipe '<name> <pubkey>' in (e.g. ssh other hm whoami | hm trust)")
		}
	default:
		return TrustRequest{}, usage.Errorf("trust takes at most two arguments, got %d", len(args))
	}
	line, err := bufio.NewReader(stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return TrustRequest{}, fmt.Errorf("reading the recipient from stdin: %w", err)
	}
	fields := strings.Fields(line)
	switch len(fields) {
	case 0:
		return TrustRequest{}, usage.Errorf("trust: empty stdin (expected '<name> <pubkey>' or '<pubkey>')")
	case 1:
		return TrustRequest{Pubkey: fields[0]}, nil
	}
	return TrustRequest{Name: fields[0], Pubkey: fields[1]}, nil
}

func AutoName(pubkey, localPubkey, hostname string) string {
	if localPubkey != "" && pubkey == localPubkey {
		return hostname
	}
	if len(pubkey) <= autoNameSuffix {
		return pubkey
	}
	return pubkey[len(pubkey)-autoNameSuffix:]
}

func ValidateTrustName(name string) error {
	if !trustNamePattern.MatchString(name) {
		return usage.Errorf("trust: name %q must match %s", name, trustNamePattern)
	}
	return nil
}

func validateRecipient(ctx context.Context, pubkey string) error {
	cmd := proc.Cmd{
		Argv:   []string{"age", "-r", pubkey, "-o", os.DevNull},
		Stdin:  strings.NewReader(""),
		Stdout: io.Discard,
		Stderr: io.Discard,
	}
	if err := proc.Run(ctx, cmd); err != nil {
		return usage.Errorf("trust: %q is not a valid age recipient pubkey", pubkey)
	}
	return nil
}

func (s Store) Trust(ctx context.Context, req TrustRequest) error {
	if err := ValidateTrustName(req.Name); err != nil {
		return err
	}
	if err := validateRecipient(ctx, req.Pubkey); err != nil {
		return err
	}
	original, err := os.ReadFile(s.configPath())
	if err != nil {
		return fmt.Errorf("trust: reading %s: %w", s.configPath(), err)
	}
	updated, added, err := AddRecipient(original, req.Pubkey, req.Name)
	if err != nil {
		return fmt.Errorf("trust: adding %s to %s: %w", req.Pubkey, s.configPath(), err)
	}
	if !added {
		s.Console.Out().Done("%s already present in .sops.yaml, nothing to do", req.Pubkey)
		return nil
	}
	if err := atomicfile.WriteKeepingMode(s.configPath(), updated); err != nil {
		return fmt.Errorf("trust: %w", err)
	}
	out := s.Console.Out()
	out.Done("Added %s → %s to .sops.yaml", out.Style.Paint(req.Name, ui.Bold), req.Pubkey)

	count, err := s.rewrapAll(ctx)
	if err != nil {
		if restoreErr := atomicfile.WriteKeepingMode(s.configPath(), original); restoreErr != nil {
			return fmt.Errorf("trust: %w; restoring .sops.yaml also failed: %w", err, restoreErr)
		}
		s.Console.Log().Warn("trust: rolled back .sops.yaml")
		return fmt.Errorf("trust: %w", err)
	}

	out.Done("Trusted %s across %d secret file(s)", out.Style.Paint(req.Name, ui.Bold), count)
	command := func(format string, args ...any) string { return out.Style.Paint(fmt.Sprintf(format, args...), ui.Cyan) }
	fmt.Fprintf(out.W, "  %s  %s\n", out.Style.Paint("Review:", ui.Bold), command("git -C %q diff -- .sops.yaml secrets/", s.Flake))
	fmt.Fprintf(out.W, "  %s  %s\n", out.Style.Paint("Commit:", ui.Bold), command("git -C %q add .sops.yaml secrets/ && \\", s.Flake))
	fmt.Fprintf(out.W, "           %s\n", command("git -C %q commit -m \"trust: add %s age recipient\"", s.Flake, req.Name))
	return nil
}

func (s Store) rewrapAll(ctx context.Context) (int, error) {
	names, err := s.SecretNames()
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	for _, name := range names {
		s.Console.Out().Step("Re-wrapping %s", name)
		if err := proc.Run(ctx, s.sops("updatekeys", "--yes", filepath.Join(s.secretsDir(), name))); err != nil {
			return 0, fmt.Errorf("re-wrapping %s: %w", name, err)
		}
	}
	return len(names), nil
}
