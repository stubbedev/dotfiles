package rebuild

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"regexp"
	"strconv"

	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

const (
	systemdRuntimeDir     = "/run/systemd/system"
	systemdOutputCatSince = 261
)

var (
	systemdRunPrefix = []string{
		"systemd-run",
		"-E", "LOCALE_ARCHIVE",
		"-E", "NIXOS_INSTALL_BOOTLOADER",
		"-E", "NIXOS_NO_CHECK",
		"--collect",
		"--no-ask-password",
		"--quiet",
		"--service-type=exec",
		"--unit=nixos-rebuild-switch-to-configuration",
	}
	systemdVersionPattern = regexp.MustCompile(`(?m)^systemd (\d+)`)
)

func switchToConfiguration(ctx context.Context, s proc.Streams, toplevel, action string, installBootloader bool) error {
	argv := []string{"env", "PATH=" + os.Getenv("PATH"), "NIXOS_INSTALL_BOOTLOADER=" + boolFlag(installBootloader)}
	for _, key := range []string{"LOCALE_ARCHIVE", "NIXOS_NO_CHECK"} {
		if v, ok := os.LookupEnv(key); ok {
			argv = append(argv, key+"="+v)
		}
	}
	prefix, err := systemdRun(ctx, s)
	if err != nil {
		return err
	}
	argv = append(argv, prefix...)
	argv = append(argv, toplevel+"/bin/switch-to-configuration", action)
	return proc.Run(ctx, proc.Cmd{Argv: elevate.Command(argv...), Stdin: s.Stdin, Stdout: s.Stderr, Stderr: s.Stderr})
}

func systemdRun(ctx context.Context, s proc.Streams) ([]string, error) {
	info, err := os.Stat(systemdRuntimeDir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("checking for a running systemd: %w", err)
	}
	if !info.IsDir() {
		return nil, nil
	}
	out, err := proc.Output(ctx, proc.Cmd{Argv: []string{"systemd-run", "--version"}, Stdin: s.Stdin, Stderr: s.Stderr})
	if err != nil {
		return nil, err
	}
	version, err := parseSystemdVersion(out)
	if err != nil {
		return nil, err
	}
	prefix := append([]string(nil), systemdRunPrefix...)
	if version >= systemdOutputCatSince {
		return append(prefix, "--wait", "--verbose", "--output=cat"), nil
	}
	return append(prefix, "--pipe"), nil
}

func parseSystemdVersion(out []byte) (int, error) {
	m := systemdVersionPattern.FindSubmatch(out)
	if m == nil {
		return 0, fmt.Errorf("parsing systemd-run --version output %q: no version line", out)
	}
	v, err := strconv.Atoi(string(m[1]))
	if err != nil {
		return 0, fmt.Errorf("parsing systemd version %q: %w", m[1], err)
	}
	return v, nil
}

func boolFlag(b bool) string {
	if b {
		return "1"
	}
	return "0"
}
