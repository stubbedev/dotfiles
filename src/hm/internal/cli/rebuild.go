package cli

import (
	"context"
	"fmt"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/flake"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
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
}

func addRebuildFlags(cmd *cobra.Command, activates bool) *rebuildFlags {
	f := &rebuildFlags{nix: addNixFlags(cmd)}
	if activates {
		cmd.Flags().BoolVar(&f.installBootloader, "install-bootloader", false, "reinstall the bootloader")
	}
	return f
}

func (f *rebuildFlags) options(cmd *cobra.Command, args []string) (rebuild.Options, error) {
	extra, err := f.nix.argv(cmd, args)
	if err != nil {
		return rebuild.Options{}, err
	}
	return rebuild.Options{InstallBootloader: f.installBootloader, Extra: extra}, nil
}

func (a *App) rebuildCmd(v rebuild.Verb) *cobra.Command {
	cmd := &cobra.Command{
		Use:     v.String() + " [flags] [-- nix build args]",
		Short:   verbSummary(v),
		GroupID: groupRebuild,
	}
	flags := addRebuildFlags(cmd, v.Activates())
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		opts, err := flags.options(cmd, args)
		if err != nil {
			return err
		}
		rt, err := a.runtime()
		if err != nil {
			return err
		}
		return withRoot(cmd.Context(), rt, rebuild.NeedsRoot(rt.Config.Platform, v), func() error {
			return rebuildAndHook(cmd.Context(), rt, v, opts)
		})
	}
	return cmd
}

func withRoot(ctx context.Context, rt rebuild.Runtime, needed bool, fn func() error) error {
	if !needed {
		return fn()
	}
	session, err := elevate.Start(ctx, rt.Streams)
	if err != nil {
		return err
	}
	defer session.Stop()
	return fn()
}

func rebuildAndHook(ctx context.Context, rt rebuild.Runtime, v rebuild.Verb, opts rebuild.Options) error {
	path, err := rebuild.Run(ctx, rt, v, opts)
	if err != nil || v != rebuild.Switch {
		return err
	}
	for _, hook := range rt.Config.PostSwitch {
		cmd := rt.Streams.Cmd(hook, path)
		cmd.Env = []string{"HM_FLAKE=" + rt.Config.Flake}
		if err := proc.Run(ctx, cmd); err != nil {
			return fmt.Errorf("post-switch hook: %w", err)
		}
	}
	return nil
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
		ValidArgsFunction: a.completeGenerations,
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
			gens, err := rebuild.ListGenerations(profile)
			if err != nil {
				return err
			}
			if cfg.Platform == config.NixOS {
				if err := rebuild.AddSystemInfo(profile, gens); err != nil {
					return err
				}
			}
			if asJSON {
				return rebuild.WriteGenerationsJSON(a.streams.Stdout, gens)
			}
			return rebuild.WriteGenerations(a.streams.Stdout, gens, cfg.Platform)
		},
	}
	cmd.Flags().BoolVar(&asJSON, "json", false, "print the generations as JSON")
	return cmd
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
	return flake.Repo{Dir: rt.Config.Flake, Ref: rt.Config.FlakeRef(), Streams: rt.Streams}
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

func (a *App) upgradeCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "upgrade [flags] [-- nix build args]",
		Short:   "Run update, then switch",
		GroupID: groupMaintain,
	}
	flags := addRebuildFlags(cmd, true)
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		opts, err := flags.options(cmd, args)
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
			return rebuildAndHook(cmd.Context(), rt, rebuild.Switch, opts)
		})
	}
	return cmd
}
