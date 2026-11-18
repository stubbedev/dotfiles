package rebuild

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	systemdRuntimeDir     = "/run/systemd/system"
	systemdOutputCatSince = 261
	switchUnit            = "nixos-rebuild-switch-to-configuration"
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
		"--unit=" + switchUnit,
	}
	unitChange            = regexp.MustCompile(`^(stopping|restarting|starting|reloading) the following (user )?units: (.+)$`)
	newUnits              = regexp.MustCompile(`^the following new units were started: (.+)$`)
	singleUnitChange      = regexp.MustCompile(`^(stopping|restarting|starting|reloading) (\S+\.(?:service|target|socket|timer|mount|path|slice))$`)
	bootloaderKept        = regexp.MustCompile(`^Skipping ".*", same boot loader version in place already\.$`)
	systemdVersionPattern = regexp.MustCompile(`(?m)^systemd (\d+)`)
)

type unitAction struct {
	icon  func(*ui.Icons) string
	label string
	color ui.Attr
}

var unitActions = map[string]unitAction{
	"stopping":   {func(i *ui.Icons) string { return i.Stop }, "stop", ui.Red},
	"restarting": {func(i *ui.Icons) string { return i.Restart }, "restart", ui.Yellow},
	"reloading":  {func(i *ui.Icons) string { return i.Reload }, "reload", ui.Cyan},
	"starting":   {func(i *ui.Icons) string { return i.Start }, "start", ui.Green},
}

const unitLabelWidth = 7

func activationFormat() ui.LineFormat {
	bootloaderReported := false
	return func(st ui.Style, line string) (string, bool) {
		if m := unitChange.FindStringSubmatch(line); m != nil {
			return unitLine(st, unitActions[m[1]], m[2] != "", strings.Split(m[3], ", ")), true
		}
		if m := newUnits.FindStringSubmatch(line); m != nil {
			return unitLine(st, unitActions["starting"], false, strings.Split(m[1], ", ")), true
		}
		if m := singleUnitChange.FindStringSubmatch(line); m != nil {
			return unitLine(st, unitActions[m[1]], false, []string{m[2]}), true
		}
		if bootloaderKept.MatchString(line) && !bootloaderReported {
			bootloaderReported = true
			ic := st.Icons()
			return st.Paint(ic.Done, ui.Green) + " " + st.Paint("bootloader up to date", ui.Faint), true
		}
		return ui.Notable(st, line)
	}
}

func unitLine(st ui.Style, action unitAction, user bool, units []string) string {
	names := make([]string, len(units))
	for i, u := range units {
		names[i] = strings.TrimSuffix(u, ".service")
	}
	label := action.icon(st.Icons()) + " " + fmt.Sprintf("%-*s", unitLabelWidth, action.label)
	line := st.Paint(label, action.color) + " " + strings.Join(names, ", ")
	if user {
		line += st.Paint(" (user)", ui.Faint)
	}
	return line
}

func switchToConfiguration(ctx context.Context, c ui.Console, toplevel, action string, installBootloader, verbose bool) error {
	argv := []string{"env", "PATH=" + os.Getenv("PATH"), "NIXOS_INSTALL_BOOTLOADER=" + boolFlag(installBootloader)}
	for _, key := range []string{"LOCALE_ARCHIVE", "NIXOS_NO_CHECK"} {
		if v, ok := os.LookupEnv(key); ok {
			argv = append(argv, key+"="+v)
		}
	}
	prefix, err := systemdRun(ctx, c.Streams)
	if err != nil {
		return err
	}
	argv = append(argv, prefix...)
	argv = append(argv, toplevel+"/bin/switch-to-configuration", action)
	return c.RunIndented(ctx, proc.Cmd{Argv: elevate.Command(argv...), Stdin: c.Stdin}, ui.Verbosity(activationFormat(), verbose))
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
