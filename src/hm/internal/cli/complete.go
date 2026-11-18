package cli

import (
	"fmt"
	"slices"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
	"github.com/stubbedev/dotfiles/src/hm/internal/rebuild"
)

func (a *App) completeSecretNames(_ *cobra.Command, args []string, _ string) ([]cobra.Completion, cobra.ShellCompDirective) {
	cfg, err := a.config()
	if len(args) > 0 || err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	names, err := a.store(cfg).SecretNames()
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	return names, cobra.ShellCompDirectiveNoFileComp
}

func (a *App) generationCompletions(maxArgs int, skip func(rebuild.Generation) bool) cobra.CompletionFunc {
	return func(_ *cobra.Command, args []string, _ string) ([]cobra.Completion, cobra.ShellCompDirective) {
		cfg, err := a.config()
		if len(args) >= maxArgs || err != nil {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		gens, err := rebuild.ListGenerations(a.profile(cfg.Platform), "")
		if err != nil {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		out := make([]cobra.Completion, 0, len(gens))
		for _, g := range gens {
			if skip(g) {
				continue
			}
			out = append(out, cobra.CompletionWithDesc(fmt.Sprint(g.ID), g.Date.Format(rebuild.DateLayout)))
		}
		return out, cobra.ShellCompDirectiveNoFileComp | cobra.ShellCompDirectiveKeepOrder
	}
}

func (a *App) completeHostAttrs(cmd *cobra.Command, _ []string, _ string) ([]cobra.Completion, cobra.ShellCompDirective) {
	if a.cfgErr != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	attrs, err := rebuild.HostAttrs(cmd.Context(), a.cfg)
	if err != nil {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	slices.Sort(attrs)
	return attrs, cobra.ShellCompDirectiveNoFileComp
}

func (a *App) externalCmd(c config.Command) *cobra.Command {
	return &cobra.Command{
		Use:                c.Name,
		Short:              c.Description,
		GroupID:            groupExtra,
		DisableFlagParsing: true,
		ValidArgsFunction: func(_ *cobra.Command, args []string, _ string) ([]cobra.Completion, cobra.ShellCompDirective) {
			if len(args) > 0 || len(c.Complete) == 0 {
				return nil, cobra.ShellCompDirectiveDefault
			}
			out := make([]cobra.Completion, len(c.Complete))
			for i, ch := range c.Complete {
				out[i] = cobra.CompletionWithDesc(ch.Name, ch.Description)
			}
			return out, cobra.ShellCompDirectiveNoFileComp
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			err := proc.Run(cmd.Context(), a.console.Cmd(append([]string{c.Exec}, args...)...))
			if code, ok := proc.ExitCode(err); ok && code > 0 {
				return &silentExit{code: code}
			}
			return err
		},
	}
}
