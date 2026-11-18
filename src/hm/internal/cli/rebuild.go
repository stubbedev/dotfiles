package cli

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/closure"
	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/flake"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
	"github.com/stubbedev/dotfiles/src/hm/internal/sops"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

func verbSummary(v rebuild.Verb) string {
	switch v {
	case rebuild.Switch:
		return "Build, show the closure diff, activate and make it the boot default"
	case rebuild.Boot:
		return "Build and make it the boot default without activating (NixOS)"
	case rebuild.Test:
		return "Build and activate without making it the boot default (NixOS)"
	case rebuild.Build:
		return "Build into ./result without activating"
	case rebuild.DryBuild:
		return "Show what would be built or fetched (NixOS)"
	case rebuild.DryActivate:
		return "Build and show what activation would change (NixOS)"
	case rebuild.BuildVM:
		return "Build a QEMU VM of the configuration (NixOS)"
	case rebuild.BuildVMWithBootloader:
		return "Build a QEMU VM that boots through the bootloader (NixOS)"
	}
	return v.String()
}

type rebuildFlags struct {
	nix               *nixFlags
	installBootloader bool
	ask               bool
	diff              rebuild.DiffOptions
}

type diffModeValue struct{ mode *rebuild.DiffMode }

func (v diffModeValue) String() string { return v.mode.String() }

func (v diffModeValue) Type() string { return "mode" }

func (v diffModeValue) Set(s string) error {
	m, err := rebuild.ParseDiffMode(s)
	if err != nil {
		return err
	}
	*v.mode = m
	return nil
}

func addRebuildFlags(cmd *cobra.Command, v rebuild.Verb) (*rebuildFlags, error) {
	f := &rebuildFlags{nix: addNixFlags(cmd)}
	fs := cmd.Flags()
	if v.Activates() {
		fs.BoolVar(&f.installBootloader, "install-bootloader", false, "reinstall the bootloader")
		fs.BoolVar(&f.ask, "ask", false, "ask for confirmation after the closure diff, before activating")
	}
	if !v.ComparesClosures() {
		return f, nil
	}
	fs.Var(diffModeValue{&f.diff.Mode}, "diff", "closure diff: auto (warn if it fails), always (fail the rebuild if it fails) or never")
	fs.BoolVar(&f.diff.Full, "diff-full", false, "also show packages whose size changed by under 1 MiB")
	if err := cmd.RegisterFlagCompletionFunc("diff", cobra.FixedCompletions(rebuild.DiffModeNames(), cobra.ShellCompDirectiveNoFileComp)); err != nil {
		return nil, fmt.Errorf("registering --diff completion: %w", err)
	}
	return f, nil
}

func (a *App) rebuildOptions(f *rebuildFlags, cmd *cobra.Command, args []string) (rebuild.Options, error) {
	extra, err := f.nix.argv(cmd, args)
	if err != nil {
		return rebuild.Options{}, err
	}
	opts := rebuild.Options{InstallBootloader: f.installBootloader, Extra: extra, Diff: f.diff, Verbose: f.nix.verbose > 0}
	if f.ask {
		if !a.terminal.StdinTTY {
			return rebuild.Options{}, usage.Errorf("%s --ask: stdin is not a terminal to answer on", cmd.CommandPath())
		}
		opts.Confirm = a.confirm
	}
	return opts, nil
}

func (a *App) confirm(question string) (bool, error) {
	fmt.Fprint(a.console.Stderr, a.console.Log().Mark(ui.MarkAsk)+" "+question+" [y/N] ")
	line, err := bufio.NewReader(a.console.Stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return false, fmt.Errorf("reading the confirmation: %w", err)
	}
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "y", "yes":
		return true, nil
	}
	return false, nil
}

func (a *App) rebuildCmd(v rebuild.Verb) (*cobra.Command, error) {
	cmd := &cobra.Command{
		Use:     v.String() + " [flags] [-- nix build args]",
		Short:   verbSummary(v),
		GroupID: groupRebuild,
	}
	flags, err := addRebuildFlags(cmd, v)
	if err != nil {
		return nil, err
	}
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		opts, err := a.rebuildOptions(flags, cmd, args)
		if err != nil {
			return err
		}
		rt, err := a.runtime()
		if err != nil {
			return err
		}
		return withRoot(cmd.Context(), rt, rebuild.NeedsRoot(rt.Config.Platform, v), func() error {
			return a.rebuildAndHook(cmd.Context(), rt, v, opts)
		})
	}
	return cmd, nil
}

func withRoot(ctx context.Context, rt rebuild.Runtime, needed bool, fn func() error) error {
	if !needed {
		return fn()
	}
	session, err := elevate.Start(ctx, rt.Console)
	if err != nil {
		return err
	}
	defer session.Stop()
	return fn()
}

func (a *App) rebuildAndHook(ctx context.Context, rt rebuild.Runtime, v rebuild.Verb, opts rebuild.Options) error {
	path, err := rebuild.Run(ctx, rt, v, opts)
	if err != nil || v != rebuild.Switch {
		return err
	}
	for _, hook := range rt.Config.PostSwitch {
		if err := a.runHook(ctx, rt, hook, path, opts.Verbose); err != nil {
			return fmt.Errorf("post-switch hook %q: %w", hook.Description, err)
		}
	}
	return nil
}

func (a *App) runHook(ctx context.Context, rt rebuild.Runtime, hook config.Hook, generation string, verbose bool) error {
	log := rt.Console.Log()
	log.StepWith(log.Style.Icons().Hook, "%s", hook.Description)
	env := []string{"HM_FLAKE=" + rt.Config.Flake}
	for _, v := range hook.Env {
		env = append(env, v.Name+"="+v.Value)
	}
	store := a.store(rt.Config)
	for _, v := range hook.SecretEnv {
		value, err := store.Decrypt(ctx, v.Value)
		var missing *sops.MissingSecretError
		if errors.As(err, &missing) {
			log.Warn("skipped: %v, run %s", missing, log.Style.Paint("hm secret set "+missing.Name, ui.Cyan))
			return nil
		}
		if err != nil {
			return err
		}
		env = append(env, v.Name+"="+string(value))
	}
	argv := append(append([]string{hook.Exec}, hook.Args...), generation)
	return rt.Console.RunIndented(ctx, proc.Cmd{Argv: argv, Env: env, Stdin: rt.Console.Stdin}, ui.Verbosity(ui.Notable, verbose))
}

func (a *App) replCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "repl [flags] [-- nix repl args]",
		Short:   "Open a nix repl on this machine's configuration",
		GroupID: groupRebuild,
	}
	flags := addNixFlags(cmd)
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		extra, err := flags.argv(cmd, args)
		if err != nil {
			return err
		}
		rt, err := a.runtime()
		if err != nil {
			return err
		}
		return rebuild.Repl(cmd.Context(), rt, extra)
	}
	return cmd
}

func (a *App) rollbackCmd() *cobra.Command {
	return &cobra.Command{
		Use:               "rollback [generation]",
		Short:             "Activate the previous generation, or the given one",
		GroupID:           groupRebuild,
		Args:              maxArgs(1),
		ValidArgsFunction: a.generationCompletions(1, func(g rebuild.Generation) bool { return g.Boot }),
		RunE: func(cmd *cobra.Command, args []string) error {
			generation := 0
			if len(args) == 1 {
				n, err := strconv.Atoi(args[0])
				if err != nil || n <= 0 {
					return usage.Errorf("rollback: %q is not a generation number", args[0])
				}
				generation = n
			}
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return rebuild.Rollback(cmd.Context(), rt, generation)
		},
	}
}

func (a *App) generationsCmd() *cobra.Command {
	var asJSON bool
	cmd := &cobra.Command{
		Use:               "generations",
		Short:             "List the system (or nix-on-droid) generations",
		GroupID:           groupRebuild,
		Args:              noArgs,
		ValidArgsFunction: cobra.NoFileCompletions,
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := a.config()
			if err != nil {
				return err
			}
			profile := a.profile(cfg.Platform)
			gens, err := rebuild.ListGenerations(profile, rebuild.RunningLink(cfg.Platform))
			if err != nil {
				return err
			}
			if cfg.Platform == config.NixOS {
				if err := rebuild.AddSystemInfo(profile, gens); err != nil {
					return err
				}
			}
			if err := rebuild.AddClosureSizes(cmd.Context(), gens); err != nil {
				return err
			}
			if asJSON {
				return rebuild.WriteGenerationsJSON(a.console.Stdout, gens)
			}
			return rebuild.WriteGenerations(a.console.Stdout, a.console.OutStyle, gens, cfg.Platform)
		},
	}
	cmd.Flags().BoolVar(&asJSON, "json", false, "print the generations as JSON")
	return cmd
}

func (a *App) diffCmd() *cobra.Command {
	var full bool
	cmd := &cobra.Command{
		Use:   "diff [old] [new]",
		Short: "Show the package changes between two generations or store paths",
		Long: `Show the package changes between two generations or store paths.

  hm diff               the previous generation against the current one
  hm diff <old>         <old> against the current generation
  hm diff <old> <new>   <old> against <new>

A number names a generation of this machine's profile; anything else is
taken as a store path or a link to one, such as ./result.`,
		GroupID:           groupRebuild,
		Args:              maxArgs(2),
		ValidArgsFunction: a.generationCompletions(2, func(rebuild.Generation) bool { return false }),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := a.config()
			if err != nil {
				return err
			}
			oldPath, newPath, err := diffPair(a.profile(cfg.Platform), args)
			if err != nil {
				return err
			}
			opts := closure.RenderOptions{Full: full, FullFlag: "--full"}
			closure.WriteHeader(a.console.Stdout, a.console.OutStyle, oldPath, newPath)
			return closure.Compare(cmd.Context(), a.console.Stdout, a.console.OutStyle, oldPath, newPath, opts)
		},
	}
	cmd.Flags().BoolVar(&full, "full", false, "also show packages whose size changed by under 1 MiB")
	return cmd
}

func diffPair(profile string, args []string) (string, string, error) {
	if len(args) == 0 {
		return rebuild.DefaultDiffPair(profile)
	}
	oldPath, err := rebuild.ResolveGeneration(profile, args[0])
	if err != nil {
		return "", "", err
	}
	if len(args) == 1 {
		return oldPath, profile, nil
	}
	newPath, err := rebuild.ResolveGeneration(profile, args[1])
	return oldPath, newPath, err
}

func (a *App) gcCmd() *cobra.Command {
	var deleteOld, dryRun bool
	var olderThan string
	cmd := &cobra.Command{
		Use:     "gc [flags] [-- nix-collect-garbage args]",
		Short:   "Collect garbage: nix-collect-garbage -d unless other flags are given",
		GroupID: groupRebuild,
		Args:    noPositionalBeforeDash,
		RunE: func(cmd *cobra.Command, args []string) error {
			var gcArgs []string
			if deleteOld {
				gcArgs = append(gcArgs, "--delete-old")
			}
			if olderThan != "" {
				gcArgs = append(gcArgs, "--delete-older-than", olderThan)
			}
			if dryRun {
				gcArgs = append(gcArgs, "--dry-run")
			}
			gcArgs = append(gcArgs, argsAfterDash(cmd, args)...)
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return rebuild.GC(cmd.Context(), rt, gcArgs)
		},
		ValidArgsFunction: cobra.NoFileCompletions,
	}
	cmd.Flags().BoolVarP(&deleteOld, "delete-old", "d", false, "delete all old generations of all profiles")
	cmd.Flags().StringVar(&olderThan, "delete-older-than", "", "delete generations older than a period, e.g. 14d")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "show what would be deleted")
	return cmd
}

func repo(rt rebuild.Runtime) flake.Repo {
	return flake.Repo{Dir: rt.Config.Flake, Ref: rt.Config.FlakeRef(), Console: rt.Console}
}

func (a *App) updateCmd() *cobra.Command {
	return &cobra.Command{
		Use:               "update",
		Short:             "Pull, update the flake inputs, commit and push flake.lock",
		GroupID:           groupMaintain,
		Args:              noArgs,
		ValidArgsFunction: cobra.NoFileCompletions,
		RunE: func(cmd *cobra.Command, _ []string) error {
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return flake.Update(cmd.Context(), repo(rt))
		},
	}
}

func (a *App) upgradeCmd() (*cobra.Command, error) {
	cmd := &cobra.Command{
		Use:     "upgrade [flags] [-- nix build args]",
		Short:   "Run update, then switch",
		GroupID: groupMaintain,
	}
	flags, err := addRebuildFlags(cmd, rebuild.Switch)
	if err != nil {
		return nil, err
	}
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		opts, err := a.rebuildOptions(flags, cmd, args)
		if err != nil {
			return err
		}
		rt, err := a.runtime()
		if err != nil {
			return err
		}
		return withRoot(cmd.Context(), rt, rebuild.NeedsRoot(rt.Config.Platform, rebuild.Switch), func() error {
			if err := flake.Update(cmd.Context(), repo(rt)); err != nil {
				return err
			}
			return a.rebuildAndHook(cmd.Context(), rt, rebuild.Switch, opts)
		})
	}
	return cmd, nil
}
