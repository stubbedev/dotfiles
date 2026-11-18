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
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/closure"
	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/nixlog"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	SystemProfile = "/nix/var/nix/profiles/system"
	DroidProfile  = "/nix/var/nix/profiles/nix-on-droid"
	currentSystem = "/run/current-system"
)

var nixFlakeFlags = []string{"--extra-experimental-features", "nix-command flakes"}

type Runtime struct {
	Config  config.Config
	Console ui.Console
	Screen  ui.Size
	Resize  <-chan ui.Size
}

type DiffMode int

const (
	DiffAuto DiffMode = iota
	DiffAlways
	DiffNever
)

var diffModeNames = []string{"auto", "always", "never"}

func DiffModeNames() []string { return slices.Clone(diffModeNames) }

func ParseDiffMode(s string) (DiffMode, error) {
	i := slices.Index(diffModeNames, s)
	if i < 0 {
		return 0, fmt.Errorf("diff mode %q: want one of %s", s, strings.Join(diffModeNames, ", "))
	}
	return DiffMode(i), nil
}

func (m DiffMode) String() string { return diffModeNames[m] }

type DiffOptions struct {
	Mode DiffMode
	Full bool
}

const diffFullFlag = "--diff-full"

var ErrDeclined = errors.New("declined to activate the new configuration")

type Options struct {
	InstallBootloader bool
	Extra             []string
	Diff              DiffOptions
	Confirm           func(question string) (bool, error)
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
	rt.Console.Log().Step("Building NixOS configuration %s", rt.Console.ErrStyle.Paint(rt.Config.Attr, ui.Bold))
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
		printResult(rt.Console, "The virtual machine can be started by running", vm)
		return path, nil
	}
	if v.ComparesClosures() {
		if err := diffClosures(ctx, rt.Console, currentSystem, path, opts.Diff); err != nil {
			return "", err
		}
	}
	if v.Activates() {
		if err := confirm(opts, v.confirmQuestion()); err != nil {
			return "", err
		}
	}
	if v.setsProfile() {
		if err := setProfile(ctx, rt.Console.Streams, path); err != nil {
			return "", err
		}
	}
	if v.Activates() {
		rt.Console.Log().Step("%s", v.activationStep())
		if err := switchToConfiguration(ctx, rt.Console.Streams, path, v.String(), opts.InstallBootloader); err != nil {
			return "", err
		}
	}
	printResult(rt.Console, "The new configuration is", path)
	return path, nil
}

func runAndroid(ctx context.Context, rt Runtime, v Verb, opts Options) (string, error) {
	if v != Switch && v != Build {
		return "", fmt.Errorf("%s: unavailable on Android; supported rebuild verbs: %s, %s", v, Switch, Build)
	}
	installable := fmt.Sprintf("%s#nixOnDroidConfigurations.%s.activationPackage", rt.Config.FlakeRef(), rt.Config.Attr)
	rt.Console.Log().Step("Building nix-on-droid configuration %s", rt.Console.ErrStyle.Paint(rt.Config.Attr, ui.Bold))
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
		if err := diffClosures(ctx, rt.Console, DroidProfile, path, opts.Diff); err != nil {
			return "", err
		}
		if err := confirm(opts, "Activate this configuration?"); err != nil {
			return "", err
		}
		rt.Console.Log().Step("Activating configuration")
		if err := proc.Run(ctx, rt.Console.Cmd(filepath.Join(path, "activate"))); err != nil {
			return "", err
		}
	}
	printResult(rt.Console, "The new configuration is", path)
	return path, nil
}

func confirm(opts Options, question string) error {
	if opts.Confirm == nil {
		return nil
	}
	ok, err := opts.Confirm(question)
	if err != nil {
		return err
	}
	if !ok {
		return ErrDeclined
	}
	return nil
}

func printResult(c ui.Console, label, path string) {
	log := c.Log()
	fmt.Fprint(c.Stderr, log.Mark(ui.MarkDone)+" "+label+" ")
	fmt.Fprintln(c.Stdout, c.OutStyle.Paint(path, ui.Bold))
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
	cache, known := loadEstimates(rt.Console.Log())
	logs, logWriter := io.Pipe()
	renderer := nixlog.NewRenderer(rt.Console.Stderr, nixlog.Config{
		Style:     rt.Console.ErrStyle,
		Width:     rt.Screen.Width,
		Height:    rt.Screen.Height,
		Resize:    rt.Resize,
		BuildLogs: spec.buildLogs(),
		Inputs:    nixlog.ReadInputDrvs,
		Estimates: known,
	})
	rendered := make(chan error, 1)
	go func() {
		rendered <- renderer.Consume(logs)
	}()
	out, err := proc.Output(ctx, proc.Cmd{Argv: spec.argv(), Stdin: rt.Console.Stdin, Stderr: logWriter})
	logWriter.Close()
	renderErr := <-rendered
	saveEstimates(rt.Console.Log(), cache, known, renderer.Measured())
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

func loadEstimates(log ui.Printer) (string, map[string]time.Duration) {
	path, err := buildTimesPath()
	if err != nil {
		log.Warn("build time estimates disabled: %v", err)
		return "", nil
	}
	known, err := loadBuildTimes(path)
	if err != nil {
		log.Warn("ignoring the build time cache, it will be rewritten: %v", err)
		return path, map[string]time.Duration{}
	}
	return path, known
}

func saveEstimates(log ui.Printer, path string, known, measured map[string]time.Duration) {
	if path == "" || len(measured) == 0 {
		return
	}
	if err := saveBuildTimes(path, mergeBuildTimes(known, measured)); err != nil {
		log.Warn("saving build time estimates: %v", err)
	}
}

func parseOutPath(out []byte) (string, error) {
	path := strings.TrimSpace(string(out))
	if path == "" || strings.ContainsAny(path, "\n ") || !filepath.IsAbs(path) {
		return "", fmt.Errorf("nix build printed %q, want exactly one store path", out)
	}
	return path, nil
}

func diffClosures(ctx context.Context, c ui.Console, current, next string, opts DiffOptions) error {
	if opts.Mode == DiffNever {
		return nil
	}
	if _, err := os.Stat(current); errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("checking the current generation %s: %w", current, err)
	}
	c.Log().Step("Comparing changes")
	err := closure.Compare(ctx, c.Stderr, c.ErrStyle, current, next, closure.RenderOptions{Full: opts.Full, FullFlag: diffFullFlag})
	if err != nil && opts.Mode == DiffAuto {
		c.Log().Warn("skipping the closure diff (--diff always makes this fatal): %v", err)
		return nil
	}
	return err
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
		return rollbackAndroid(ctx, rt.Console, DroidProfile, generation)
	}
	argv := elevate.Command("nix-env", "--rollback", "-p", SystemProfile)
	if generation > 0 {
		argv = elevate.Command("nix-env", "--switch-generation", strconv.Itoa(generation), "-p", SystemProfile)
	}
	rt.Console.Log().Step("Rolling back the system profile")
	if err := proc.Run(ctx, proc.Cmd{Argv: argv, Stdin: rt.Console.Stdin, Stdout: rt.Console.Stderr, Stderr: rt.Console.Stderr}); err != nil {
		return err
	}
	rt.Console.Log().Step("%s", Switch.activationStep())
	return switchToConfiguration(ctx, rt.Console.Streams, SystemProfile, Switch.String(), false)
}

func rollbackAndroid(ctx context.Context, c ui.Console, profile string, generation int) error {
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
	c.Log().Step("Activating %s", target)
	return proc.Run(ctx, c.Cmd(activate))
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

func Repl(ctx context.Context, rt Runtime, extra []string) error {
	attr := fmt.Sprintf("nixosConfigurations.%s", rt.Config.Attr)
	if rt.Config.Platform == config.Android {
		attr = fmt.Sprintf("nixOnDroidConfigurations.%s", rt.Config.Attr)
	}
	argv := append([]string{"nix"}, nixFlakeFlags...)
	argv = append(argv, "repl", rt.Config.FlakeRef()+"#"+attr)
	return proc.Run(ctx, rt.Console.Cmd(append(argv, extra...)...))
}

func GC(ctx context.Context, rt Runtime, args []string) error {
	if len(args) == 0 {
		args = []string{"-d"}
	}
	argv := append([]string{"nix-collect-garbage"}, args...)
	if rt.Config.Platform == config.NixOS {
		argv = elevate.Command(argv...)
	}
	rt.Console.Log().Step("Collecting garbage")
	return proc.Run(ctx, rt.Console.Cmd(argv...))
}
