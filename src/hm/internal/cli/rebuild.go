package cli

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/elevate"
	"github.com/stubbedev/dotfiles/src/hm/internal/flake"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
)

const installBootloaderFlag = "--install-bootloader"

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

func (a *App) rebuildCmd(v rebuild.Verb) *cobra.Command {
	use := v.String() + " [nix build flags]"
	flags := nixBuildFlags
	if v.Activates() {
		use = v.String() + " [" + installBootloaderFlag + "] [nix build flags]"
		flags = append([]flagCompletion{{installBootloaderFlag, "Reinstall the bootloader"}}, nixBuildFlags...)
	}
	return &cobra.Command{
		Use:                use,
		Short:              verbSummary(v),
		GroupID:            groupRebuild,
		DisableFlagParsing: true,
		ValidArgsFunction:  completeFlags(flags),
		RunE: func(cmd *cobra.Command, args []string) error {
			if wantsHelp(args) {
				return cmd.Help()
			}
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			opts := parseRebuildArgs(args)
			return withRoot(cmd.Context(), rt, rebuild.NeedsRoot(rt.Config.Platform, v), func() error {
				return rebuildAndHook(cmd.Context(), rt, v, opts)
			})
		},
	}
}

func parseRebuildArgs(args []string) rebuild.Options {
	opts := rebuild.Options{Extra: make([]string, 0, len(args))}
	for _, arg := range args {
		if arg == installBootloaderFlag {
			opts.InstallBootloader = true
			continue
		}
		opts.Extra = append(opts.Extra, arg)
	}
	return opts
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
	return &cobra.Command{
		Use:                "repl [nix repl flags]",
		Short:              "Open a nix repl on this machine's configuration",
		GroupID:            groupRebuild,
		DisableFlagParsing: true,
		ValidArgsFunction:  completeFlags(nixBuildFlags),
		RunE: func(cmd *cobra.Command, args []string) error {
			if wantsHelp(args) {
				return cmd.Help()
			}
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return rebuild.Repl(cmd.Context(), rt, args)
		},
	}
}

func (a *App) rollbackCmd() *cobra.Command {
	return &cobra.Command{
		Use:               "rollback",
		Short:             "Roll back to the previous generation and activate it",
		GroupID:           groupRebuild,
		Args:              noArgs,
		ValidArgsFunction: cobra.NoFileCompletions,
		RunE: func(cmd *cobra.Command, _ []string) error {
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return rebuild.Rollback(cmd.Context(), rt)
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
			gens, err := rebuild.ListGenerations(rebuild.Profile(cfg.Platform), cfg.Platform)
			if err != nil {
				return err
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
	return &cobra.Command{
		Use:                "gc [nix-collect-garbage flags]",
		Short:              "Collect garbage: nix-collect-garbage -d, or with the given flags",
		GroupID:            groupRebuild,
		DisableFlagParsing: true,
		ValidArgsFunction:  completeFlags(gcFlags),
		RunE: func(cmd *cobra.Command, args []string) error {
			if wantsHelp(args) {
				return cmd.Help()
			}
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			return rebuild.GC(cmd.Context(), rt, args)
		},
	}
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
	return &cobra.Command{
		Use:                "upgrade [" + installBootloaderFlag + "] [nix build flags]",
		Short:              "Run update, then switch",
		GroupID:            groupMaintain,
		DisableFlagParsing: true,
		ValidArgsFunction:  completeFlags(nixBuildFlags),
		RunE: func(cmd *cobra.Command, args []string) error {
			if wantsHelp(args) {
				return cmd.Help()
			}
			rt, err := a.runtime()
			if err != nil {
				return err
			}
			opts := parseRebuildArgs(args)
			return withRoot(cmd.Context(), rt, rebuild.NeedsRoot(rt.Config.Platform, rebuild.Switch), func() error {
				if err := flake.Update(cmd.Context(), repo(rt)); err != nil {
					return err
				}
				return rebuildAndHook(cmd.Context(), rt, rebuild.Switch, opts)
			})
		},
	}
}
