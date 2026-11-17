package rebuild

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/nixlog"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

const (
	SystemProfile = "/nix/var/nix/profiles/system"
	DroidProfile  = "/nix/var/nix/profiles/nix-on-droid"
	currentSystem = "/run/current-system"
)

var nixFlakeFlags = []string{"--extra-experimental-features", "nix-command flakes"}

type Runtime struct {
	Config   config.Config
	Streams  proc.Streams
	TTYWidth int
}

type Options struct {
	InstallBootloader bool
	Extra             []string
}

func Profile(p config.Platform) string {
	if p == config.Android {
		return DroidProfile
	}
	return SystemProfile
}

func NeedsRoot(p config.Platform, v Verb) bool {
	return p == config.NixOS && v.Activates()
}

func Run(ctx context.Context, rt Runtime, v Verb, opts Options) (string, error) {
	if opts.InstallBootloader && !v.Activates() {
		return "", fmt.Errorf("%s: --install-bootloader only applies to verbs that activate", v)
	}
	if rt.Config.Platform == config.Android {
		return runAndroid(ctx, rt, v, opts)
	}
	return runNixOS(ctx, rt, v, opts)
}

func runNixOS(ctx context.Context, rt Runtime, v Verb, opts Options) (string, error) {
	installable := fmt.Sprintf("%s#nixosConfigurations.%s.%s", rt.Config.FlakeRef(), rt.Config.Attr, v.nixosAttr())
	path, err := nixBuild(ctx, rt, buildSpec{
		installable: installable,
		linkResult:  v.linksResult(),
		dryRun:      v == DryBuild,
		extra:       opts.Extra,
	})
	if err != nil || v == DryBuild {
		return "", err
	}
	if v.buildsVM() {
		vm, err := findVM(path)
		if err != nil {
			return "", err
		}
		fmt.Fprint(rt.Streams.Stderr, "Done. The virtual machine can be started by running ")
		fmt.Fprintln(rt.Streams.Stdout, vm)
		return path, nil
	}
	if err := diffClosures(ctx, rt.Streams, currentSystem, path); err != nil {
		return "", err
	}
	if v.setsProfile() {
		if err := setProfile(ctx, rt.Streams, path); err != nil {
			return "", err
		}
	}
	if v.Activates() {
		if err := switchToConfiguration(ctx, rt.Streams, path, v.String(), opts.InstallBootloader); err != nil {
			return "", err
		}
	}
	printDone(rt.Streams, path)
	return path, nil
}

func runAndroid(ctx context.Context, rt Runtime, v Verb, opts Options) (string, error) {
	if v != Switch && v != Build {
		return "", fmt.Errorf("%s: unavailable on Android; supported rebuild verbs: %s, %s", v, Switch, Build)
	}
	installable := fmt.Sprintf("%s#nixOnDroidConfigurations.%s.activationPackage", rt.Config.FlakeRef(), rt.Config.Attr)
	path, err := nixBuild(ctx, rt, buildSpec{
		installable: installable,
		linkResult:  v == Build,
		impure:      true,
		extra:       opts.Extra,
	})
	if err != nil {
		return "", err
	}
	if v == Switch {
		if err := diffClosures(ctx, rt.Streams, DroidProfile, path); err != nil {
			return "", err
		}
		if err := proc.Run(ctx, rt.Streams.Cmd(filepath.Join(path, "activate"))); err != nil {
			return "", err
		}
	}
	printDone(rt.Streams, path)
	return path, nil
}

func printDone(s proc.Streams, path string) {
	fmt.Fprint(s.Stderr, "Done. The new configuration is ")
	fmt.Fprintln(s.Stdout, path)
}

type buildSpec struct {
	installable string
	linkResult  bool
	dryRun      bool
	impure      bool
	extra       []string
}

func (b buildSpec) argv() []string {
	argv := append([]string{"nix"}, nixFlakeFlags...)
	argv = append(argv, "build", "--log-format", "internal-json", "--print-out-paths")
	if !b.linkResult {
		argv = append(argv, "--no-link")
	}
	if b.dryRun {
		argv = append(argv, "--dry-run")
	}
	if b.impure {
		argv = append(argv, "--impure")
	}
	argv = append(argv, b.installable)
	return append(argv, b.extra...)
}

func (b buildSpec) buildLogs() bool {
	return slices.Contains(b.extra, "-L") || slices.Contains(b.extra, "--print-build-logs")
}

func nixBuild(ctx context.Context, rt Runtime, spec buildSpec) (string, error) {
	logs, logWriter := io.Pipe()
	renderer := nixlog.NewRenderer(rt.Streams.Stderr, rt.TTYWidth, spec.buildLogs())
	rendered := make(chan error, 1)
	go func() {
		rendered <- renderer.Consume(logs)
	}()
	out, err := proc.Output(ctx, proc.Cmd{Argv: spec.argv(), Stdin: rt.Streams.Stdin, Stderr: logWriter})
	logWriter.Close()
	renderErr := <-rendered
	if err != nil {
		return "", err
	}
	if renderErr != nil {
		return "", renderErr
	}
	if spec.dryRun {
		return "", nil
	}
	return parseOutPath(out)
}

func parseOutPath(out []byte) (string, error) {
	path := strings.TrimSpace(string(out))
	if path == "" || strings.ContainsAny(path, "\n ") || !filepath.IsAbs(path) {
		return "", fmt.Errorf("nix build printed %q, want exactly one store path", out)
	}
	return path, nil
}

func diffClosures(ctx context.Context, s proc.Streams, current, next string) error {
	if _, err := os.Stat(current); errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("checking the current generation %s: %w", current, err)
	}
	fmt.Fprintf(s.Stderr, "<<< %s\n>>> %s\n", current, next)
	argv := append([]string{"nix"}, nixFlakeFlags...)
	argv = append(argv, "store", "diff-closures", current, next)
	return proc.Run(ctx, proc.Cmd{Argv: argv, Stdin: s.Stdin, Stdout: s.Stderr, Stderr: s.Stderr})
}

func setProfile(ctx context.Context, s proc.Streams, toplevel string) error {
	if _, err := os.Stat(filepath.Join(toplevel, "nixos-version")); err != nil {
		return fmt.Errorf("refusing to activate %s, it does not look like a NixOS system: %w", toplevel, err)
	}
	argv := elevate.Command("nix-env", "-p", SystemProfile, "--set", toplevel)
	return proc.Run(ctx, proc.Cmd{Argv: argv, Stdin: s.Stdin, Stdout: s.Stderr, Stderr: s.Stderr})
}

func findVM(path string) (string, error) {
	matches, err := filepath.Glob(filepath.Join(path, "bin", "run-*-vm"))
	if err != nil {
		return "", fmt.Errorf("locating the VM runner in %s: %w", path, err)
	}
	if len(matches) != 1 {
		return "", fmt.Errorf("locating the VM runner in %s: found %d bin/run-*-vm scripts, want 1", path, len(matches))
	}
	return matches[0], nil
}

func Rollback(ctx context.Context, rt Runtime, generation int) error {
	if generation < 0 {
		return fmt.Errorf("rollback: generation %d is not a generation number", generation)
	}
	if rt.Config.Platform == config.Android {
		return rollbackAndroid(ctx, rt.Streams, DroidProfile, generation)
	}
	argv := elevate.Command("nix-env", "--rollback", "-p", SystemProfile)
	if generation > 0 {
		argv = elevate.Command("nix-env", "--switch-generation", strconv.Itoa(generation), "-p", SystemProfile)
	}
	if err := proc.Run(ctx, proc.Cmd{Argv: argv, Stdin: rt.Streams.Stdin, Stdout: rt.Streams.Stderr, Stderr: rt.Streams.Stderr}); err != nil {
		return err
	}
	return switchToConfiguration(ctx, rt.Streams, SystemProfile, Switch.String(), false)
}

func rollbackAndroid(ctx context.Context, s proc.Streams, profile string, generation int) error {
	target := generationPath(profile, generation)
	if generation == 0 {
		previous, err := previousGeneration(profile)
		if err != nil {
			return err
		}
		target = previous
	}
	activate := filepath.Join(target, "activate")
	info, err := os.Stat(activate)
	if err != nil || info.Mode()&0o111 == 0 {
		return fmt.Errorf("rolling back to %s: no executable activate script, the generation is broken or garbage collected", target)
	}
	fmt.Fprintln(s.Stderr, "Executing activation script...")
	return proc.Run(ctx, s.Cmd(activate))
}

func HostAttrs(ctx context.Context, cfg config.Config) ([]string, error) {
	set := "nixosConfigurations"
	if cfg.Platform == config.Android {
		set = "nixOnDroidConfigurations"
	}
	argv := append([]string{"nix"}, nixFlakeFlags...)
	argv = append(argv, "eval", "--json", cfg.FlakeRef()+"#"+set, "--apply", "builtins.attrNames")
	out, err := proc.Output(ctx, proc.Cmd{Argv: argv, Stdin: strings.NewReader(""), Stderr: io.Discard})
	if err != nil {
		return nil, fmt.Errorf("listing %s: %w", set, err)
	}
	var attrs []string
	if err := json.Unmarshal(out, &attrs); err != nil {
		return nil, fmt.Errorf("listing %s: decoding %q: %w", set, out, err)
	}
	return attrs, nil
}

func previousGeneration(profile string) (string, error) {
	target, err := os.Readlink(profile)
	if err != nil {
		return "", fmt.Errorf("reading the current generation of %s: %w", profile, err)
	}
	id, ok := generationID(filepath.Base(profile), filepath.Base(target))
	if !ok {
		return "", fmt.Errorf("profile link %s points at %s, not a generation", profile, target)
	}
	if id <= 1 {
		return "", fmt.Errorf("generation %d of %s has no predecessor", id, profile)
	}
	return generationPath(profile, id-1), nil
}

func Repl(ctx context.Context, rt Runtime, extra []string) error {
	attr := fmt.Sprintf("nixosConfigurations.%s", rt.Config.Attr)
	if rt.Config.Platform == config.Android {
		attr = fmt.Sprintf("nixOnDroidConfigurations.%s", rt.Config.Attr)
	}
	argv := append([]string{"nix"}, nixFlakeFlags...)
	argv = append(argv, "repl", rt.Config.FlakeRef()+"#"+attr)
	return proc.Run(ctx, rt.Streams.Cmd(append(argv, extra...)...))
}

func GC(ctx context.Context, rt Runtime, args []string) error {
	if len(args) == 0 {
		args = []string{"-d"}
	}
	argv := append([]string{"nix-collect-garbage"}, args...)
	if rt.Config.Platform == config.NixOS {
		argv = elevate.Command(argv...)
	}
	return proc.Run(ctx, rt.Streams.Cmd(argv...))
}
