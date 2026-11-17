package cli

import (
	"strings"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/config"
	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

type flagCompletion struct {
	flag        string
	description string
}

var nixBuildFlags = []flagCompletion{
	{"--show-trace", "Show trace on evaluation errors"},
	{"--print-build-logs", "Print full build logs"},
	{"-L", "Print full build logs"},
	{"--keep-failed", "Keep the build directory of failed builds"},
	{"--keep-going", "Keep building other derivations after a failure"},
	{"--max-jobs", "Maximum number of parallel builds"},
	{"--cores", "Cores per build"},
	{"--option", "Set a nix option: --option <name> <value>"},
	{"--builders", "Remote builders to use"},
	{"--fallback", "Build from source when substitution fails"},
	{"--offline", "Do not use the network"},
	{"--refresh", "Treat cached flake inputs as out of date"},
	{"--override-input", "Override a flake input: --override-input <input> <ref>"},
	{"--no-write-lock-file", "Do not write flake.lock"},
	{"--impure", "Allow impure evaluation"},
	{"--verbose", "Increase verbosity"},
}

var gcFlags = []flagCompletion{
	{"-d", "Delete all old generations of all profiles"},
	{"--delete-old", "Delete all old generations of all profiles"},
	{"--delete-older-than", "Delete generations older than a period, e.g. 14d"},
	{"--dry-run", "Show what would be deleted"},
}

func completeFlags(flags []flagCompletion) cobra.CompletionFunc {
	return func(_ *cobra.Command, _ []string, toComplete string) ([]cobra.Completion, cobra.ShellCompDirective) {
		if !strings.HasPrefix(toComplete, "-") {
			return nil, cobra.ShellCompDirectiveDefault
		}
		out := make([]cobra.Completion, 0, len(flags))
		for _, f := range flags {
			if strings.HasPrefix(f.flag, toComplete) {
				out = append(out, cobra.CompletionWithDesc(f.flag, f.description))
			}
		}
		return out, cobra.ShellCompDirectiveNoFileComp
	}
}

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
			err := proc.Run(cmd.Context(), a.streams.Cmd(append([]string{c.Exec}, args...)...))
			if code, ok := proc.ExitCode(err); ok && code > 0 {
				return &silentExit{code: code}
			}
			return err
		},
	}
}
