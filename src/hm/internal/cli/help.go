package cli

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strings"

	"github.com/spf13/cobra"

	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

var (
	helpHeading = regexp.MustCompile(`^[A-Z][A-Za-z ]*:$`)
	flagSpecEnd = regexp.MustCompile(`\S {2,}`)
)

func helpCommands(c *cobra.Command) []*cobra.Command {
	var out []*cobra.Command
	for _, sub := range c.Commands() {
		if sub.IsAvailableCommand() || sub.Name() == "help" {
			out = append(out, sub)
		}
	}
	return out
}

func (a *App) installHelp(root *cobra.Command) {
	root.SetHelpFunc(func(c *cobra.Command, _ []string) {
		if err := writeHelp(c.OutOrStdout(), a.console.OutStyle, c); err != nil {
			a.console.Log().Error(err)
		}
	})
	root.SetUsageFunc(func(c *cobra.Command) error {
		return writeUsage(c.OutOrStderr(), ui.Style{}, c)
	})
}

func writeHelp(w io.Writer, st ui.Style, c *cobra.Command) error {
	bw := bufio.NewWriter(w)
	text := c.Long
	if text == "" {
		text = c.Short
	}
	if text = strings.TrimRight(text, " \t\n"); text != "" {
		for _, line := range strings.Split(text, "\n") {
			if helpHeading.MatchString(line) {
				line = heading(st, line)
			}
			bw.WriteString(line + "\n")
		}
		bw.WriteString("\n")
	}
	if c.Runnable() || c.HasSubCommands() {
		renderUsage(bw, st, c)
	}
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("writing help for %s: %w", c.CommandPath(), err)
	}
	return nil
}

func writeUsage(w io.Writer, st ui.Style, c *cobra.Command) error {
	bw := bufio.NewWriter(w)
	renderUsage(bw, st, c)
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("writing usage for %s: %w", c.CommandPath(), err)
	}
	return nil
}

func heading(st ui.Style, s string) string { return st.Paint(s, ui.Bold, ui.Yellow) }

func renderUsage(w *bufio.Writer, st ui.Style, c *cobra.Command) {
	w.WriteString(heading(st, "Usage:"))
	if c.Runnable() {
		w.WriteString("\n  " + c.UseLine())
	}
	if c.HasAvailableSubCommands() {
		w.WriteString("\n  " + c.CommandPath() + " [command]")
	}
	if len(c.Aliases) > 0 {
		w.WriteString("\n\n" + heading(st, "Aliases:") + "\n  " + c.NameAndAliases())
	}
	if c.HasExample() {
		w.WriteString("\n\n" + heading(st, "Examples:") + "\n" + c.Example)
	}
	if c.HasAvailableSubCommands() {
		commandSections(w, st, c)
	}
	if c.HasAvailableLocalFlags() {
		w.WriteString("\n\n" + heading(st, "Flags:") + "\n" + flagUsages(st, c.LocalFlags().FlagUsages()))
	}
	if c.HasAvailableInheritedFlags() {
		w.WriteString("\n\n" + heading(st, "Global Flags:") + "\n" + flagUsages(st, c.InheritedFlags().FlagUsages()))
	}
	if c.HasAvailableSubCommands() {
		hint := fmt.Sprintf("%q", c.CommandPath()+" [command] --help")
		w.WriteString("\n\nUse " + st.Paint(hint, ui.Cyan) + " for more information about a command.")
	}
	w.WriteString("\n")
}

func commandSections(w *bufio.Writer, st ui.Style, c *cobra.Command) {
	commands := helpCommands(c)
	section := func(title string, member func(*cobra.Command) bool) {
		var lines []string
		for _, sub := range commands {
			if member(sub) {
				name := st.Paint(sub.Name()+strings.Repeat(" ", max(sub.NamePadding()-len(sub.Name()), 0)), ui.Bold, ui.Green)
				lines = append(lines, "  "+name+" "+sub.Short)
			}
		}
		if len(lines) > 0 {
			w.WriteString("\n\n" + heading(st, title) + "\n" + strings.Join(lines, "\n"))
		}
	}
	if len(c.Groups()) == 0 {
		section("Available Commands:", func(*cobra.Command) bool { return true })
		return
	}
	for _, g := range c.Groups() {
		section(g.Title, func(sub *cobra.Command) bool { return sub.GroupID == g.ID })
	}
	section("Additional Commands:", func(sub *cobra.Command) bool { return sub.GroupID == "" })
}

func flagUsages(st ui.Style, usages string) string {
	lines := strings.Split(strings.TrimRight(usages, " \t\n"), "\n")
	for i, line := range lines {
		trimmed := strings.TrimLeft(line, " ")
		if !strings.HasPrefix(trimmed, "-") {
			continue
		}
		indent := line[:len(line)-len(trimmed)]
		end := len(trimmed)
		if loc := flagSpecEnd.FindStringIndex(trimmed); loc != nil {
			end = loc[0] + 1
		}
		lines[i] = indent + st.Paint(trimmed[:end], ui.Bold, ui.Red) + trimmed[end:]
	}
	return strings.Join(lines, "\n")
}
