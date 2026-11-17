package cli

import (
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/pflag"

	"github.com/stubbedev/dotfiles/src/hm/internal/usage"
)

type nixFlags struct {
	flags          *pflag.FlagSet
	showTrace      bool
	printBuildLogs bool
	keepGoing      bool
	keepFailed     bool
	fallback       bool
	offline        bool
	refresh        bool
	impure         bool
	verbose        int
	maxJobs        string
	cores          int
	builders       string
	options        []string
	overrideInputs []string
}

func addNixFlags(cmd *cobra.Command) *nixFlags {
	f := &nixFlags{flags: cmd.Flags()}
	fs := cmd.Flags()
	fs.BoolVar(&f.showTrace, "show-trace", false, "show the trace of evaluation errors")
	fs.BoolVarP(&f.printBuildLogs, "print-build-logs", "L", false, "print full build logs")
	fs.BoolVarP(&f.keepGoing, "keep-going", "k", false, "keep building other derivations after a failure")
	fs.BoolVarP(&f.keepFailed, "keep-failed", "K", false, "keep the build directory of failed builds")
	fs.BoolVar(&f.fallback, "fallback", false, "build from source when substitution fails")
	fs.BoolVar(&f.offline, "offline", false, "do not use the network")
	fs.BoolVar(&f.refresh, "refresh", false, "treat cached flake inputs as out of date")
	fs.BoolVar(&f.impure, "impure", false, "allow impure evaluation")
	fs.CountVarP(&f.verbose, "verbose", "v", "increase nix verbosity (repeatable)")
	fs.StringVarP(&f.maxJobs, "max-jobs", "j", "", "maximum number of parallel builds (a number or auto)")
	fs.IntVar(&f.cores, "cores", 0, "cores per build (0 lets nix decide)")
	fs.StringVar(&f.builders, "builders", "", "remote builders to use")
	fs.StringArrayVar(&f.options, "option", nil, "set a nix option, as name=value (repeatable)")
	fs.StringArrayVar(&f.overrideInputs, "override-input", nil, "override a flake input, as input=flakeref (repeatable)")
	cmd.Args = noPositionalBeforeDash
	cmd.ValidArgsFunction = cobra.NoFileCompletions
	return f
}

func (f *nixFlags) argv(cmd *cobra.Command, args []string) ([]string, error) {
	var out []string
	for _, b := range []struct {
		set  bool
		flag string
	}{
		{f.showTrace, "--show-trace"},
		{f.printBuildLogs, "--print-build-logs"},
		{f.keepGoing, "--keep-going"},
		{f.keepFailed, "--keep-failed"},
		{f.fallback, "--fallback"},
		{f.offline, "--offline"},
		{f.refresh, "--refresh"},
		{f.impure, "--impure"},
	} {
		if b.set {
			out = append(out, b.flag)
		}
	}
	for range f.verbose {
		out = append(out, "-v")
	}
	if f.flags.Changed("max-jobs") {
		out = append(out, "--max-jobs", f.maxJobs)
	}
	if f.flags.Changed("cores") {
		out = append(out, "--cores", strconv.Itoa(f.cores))
	}
	if f.flags.Changed("builders") {
		out = append(out, "--builders", f.builders)
	}
	pairs := []struct {
		flag   string
		values []string
	}{{"--option", f.options}, {"--override-input", f.overrideInputs}}
	for _, p := range pairs {
		for _, v := range p.values {
			name, value, ok := strings.Cut(v, "=")
			if !ok || name == "" {
				return nil, usage.Errorf("%s %q: want name=value", p.flag, v)
			}
			out = append(out, p.flag, name, value)
		}
	}
	return append(out, argsAfterDash(cmd, args)...), nil
}

func noPositionalBeforeDash(cmd *cobra.Command, args []string) error {
	before := len(args)
	if dash := cmd.ArgsLenAtDash(); dash >= 0 {
		before = dash
	}
	if before > 0 {
		return usage.Errorf("%s: unexpected argument %q; pass raw nix arguments after --", cmd.CommandPath(), args[0])
	}
	return nil
}

func argsAfterDash(cmd *cobra.Command, args []string) []string {
	if dash := cmd.ArgsLenAtDash(); dash >= 0 {
		return args[dash:]
	}
	return nil
}
