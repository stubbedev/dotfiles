package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"slices"
	"syscall"

	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

const (
	groupRebuild  = "rebuild"
	groupMaintain = "maintain"
	groupExtra    = "extra"
)

var reservedNames = []string{"help", "completion"}

type Terminal struct {
	StdinTTY bool
	Stdout   ui.Style
	Stderr   ui.Style
	Screen   ui.Size
	Resize   <-chan ui.Size
}

type App struct {
	console  ui.Console
	terminal Terminal
	cfg      config.Config
	cfgErr   error
	attr     string
	profile  func(config.Platform) string
}

func Main(args []string) int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	streams := proc.Streams{Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr}
	return New(streams, detectTerminal(ctx)).Run(ctx, args)
}

func detectTerminal(ctx context.Context) Terminal {
	icons := ui.DetectIcons(os.Getenv)
	t := Terminal{
		StdinTTY: term.IsTerminal(int(os.Stdin.Fd())),
		Stdout:   ui.NewStyle(ui.DetectColor(os.Stdout, os.Getenv), icons),
		Stderr:   ui.NewStyle(ui.DetectColor(os.Stderr, os.Getenv), icons),
	}
	if os.Getenv("TERM") == "dumb" || !term.IsTerminal(int(os.Stderr.Fd())) {
		return t
	}
	if width, height, err := term.GetSize(int(os.Stderr.Fd())); err == nil {
		t.Screen = ui.Size{Width: width, Height: height}
		t.Resize = ui.WatchSize(ctx, os.Stderr)
	}
	return t
}

func New(streams proc.Streams, terminal Terminal) *App {
	a := &App{
		console:  ui.Console{Streams: streams, OutStyle: terminal.Stdout, ErrStyle: terminal.Stderr},
		terminal: terminal,
		profile:  rebuild.Profile,
	}
	path, err := config.DefaultPath(os.Getenv)
	if err == nil {
		a.cfg, err = config.Load(path, os.Getenv)
	}
	a.cfgErr = err
	return a
}

func (a *App) Run(ctx context.Context, args []string) int {
	root, err := a.root()
	if err == nil {
		root.SetArgs(args)
		err = root.ExecuteContext(ctx)
	}
	if err == nil {
		return 0
	}
	var silent *silentExit
	if errors.As(err, &silent) {
		return silent.code
	}
	if errors.Is(err, rebuild.ErrDeclined) {
		a.console.Log().Warn("Not activating, nothing was changed")
		return 1
	}
	a.console.Log().Error(err)
	return exitCode(err)
}

type silentExit struct {
	code int
}

func (e *silentExit) Error() string { return fmt.Sprintf("exit status %d", e.code) }

func exitCode(err error) int {
	if usage.Is(err) {
		return 2
	}
	if code, ok := proc.ExitCode(err); ok && code > 0 {
		return code
	}
	return 1
}

func (a *App) config() (config.Config, error) {
	if a.cfgErr != nil {
		return config.Config{}, a.cfgErr
	}
	cfg := a.cfg
	if a.attr != "" {
		if err := config.ValidateAttr(a.attr); err != nil {
			return config.Config{}, usage.Wrap(fmt.Errorf("--attr: %w", err))
		}
		cfg.Attr = a.attr
	}
	return cfg, nil
}

func (a *App) runtime() (rebuild.Runtime, error) {
	cfg, err := a.config()
	if err != nil {
		return rebuild.Runtime{}, err
	}
	return rebuild.Runtime{Config: cfg, Console: a.console, Screen: a.terminal.Screen, Resize: a.terminal.Resize}, nil
}

func (a *App) root() (*cobra.Command, error) {
	root := &cobra.Command{
		Use:   "hm",
		Short: "Build, activate and maintain this machine's flake configuration",
		Long: `hm builds and activates this machine's configuration from the flake checkout,
and maintains the flake: input updates, sops secrets and age recipients.

Rebuilds evaluate and build as you with nix build, show the closure diff
against the running generation, and only activation runs as root.

Environment:
  HM_CONFIG        config file (default: $XDG_CONFIG_HOME/hm/config.json)
  HM_FLAKE_DIR     flake directory, overriding the config
  HM_NIXOS_CONFIG  nixosConfigurations attribute, overriding the config
                   (--attr overrides both)
  NO_COLOR         disable colored output
  FORCE_COLOR      color output even when it is not a terminal
  NERD_FONTS       1 or 0 to force Nerd Font icons on or off in the build view`,
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          a.rejectUnknown,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if err := writeHelp(a.console.Stderr, a.console.ErrStyle, cmd); err != nil {
				return err
			}
			return usage.Errorf("no command given")
		},
	}
	a.installHelp(root)
	root.SetIn(a.console.Stdin)
	root.SetOut(a.console.Stdout)
	root.SetErr(a.console.Stderr)
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error { return usage.Wrap(err) })
	root.PersistentFlags().StringVar(&a.attr, "attr", "", "configuration attribute to build, overriding the config and HM_NIXOS_CONFIG")
	if err := root.RegisterFlagCompletionFunc("attr", a.completeHostAttrs); err != nil {
		return nil, fmt.Errorf("registering --attr completion: %w", err)
	}
	root.AddGroup(
		&cobra.Group{ID: groupRebuild, Title: "Rebuild:"},
		&cobra.Group{ID: groupMaintain, Title: "Maintenance:"},
	)
	for _, v := range rebuild.Verbs() {
		cmd, err := a.rebuildCmd(v)
		if err != nil {
			return nil, err
		}
		root.AddCommand(cmd)
	}
	upgrade, err := a.upgradeCmd()
	if err != nil {
		return nil, err
	}
	root.AddCommand(
		a.replCmd(),
		a.rollbackCmd(),
		a.generationsCmd(),
		a.diffCmd(),
		a.gcCmd(),
		a.updateCmd(),
		upgrade,
		a.whoamiCmd(),
		a.trustCmd(),
		a.secretCmd(),
	)
	if a.cfgErr != nil || len(a.cfg.Commands) == 0 {
		return root, nil
	}
	taken := slices.Clone(reservedNames)
	for _, c := range root.Commands() {
		taken = append(taken, c.Name())
	}
	root.AddGroup(&cobra.Group{ID: groupExtra, Title: "Extra:"})
	for _, c := range a.cfg.Commands {
		if slices.Contains(taken, c.Name) {
			return nil, fmt.Errorf("config command %q collides with a built-in command", c.Name)
		}
		root.AddCommand(a.externalCmd(c))
	}
	return root, nil
}

func (a *App) rejectUnknown(_ *cobra.Command, args []string) error {
	if len(args) == 0 {
		return nil
	}
	if a.cfgErr != nil {
		return usage.Errorf("unknown command %q; try 'hm help' (extra commands unavailable: %v)", args[0], a.cfgErr)
	}
	return usage.Errorf("unknown command %q; try 'hm help'", args[0])
}

func noArgs(cmd *cobra.Command, args []string) error {
	if len(args) > 0 {
		return usage.Errorf("%s takes no arguments, got %q", cmd.CommandPath(), args)
	}
	return nil
}

func exactArgs(n int) cobra.PositionalArgs {
	return func(cmd *cobra.Command, args []string) error {
		if len(args) != n {
			return usage.Errorf("%s takes %d argument(s), got %d; usage: %s", cmd.CommandPath(), n, len(args), cmd.UseLine())
		}
		return nil
	}
}

func maxArgs(n int) cobra.PositionalArgs {
	return func(cmd *cobra.Command, args []string) error {
		if len(args) > n {
			return usage.Errorf("%s takes at most %d argument(s), got %d; usage: %s", cmd.CommandPath(), n, len(args), cmd.UseLine())
		}
		return nil
	}
}
