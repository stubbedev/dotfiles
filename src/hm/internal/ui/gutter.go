package ui

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

type LineFormat func(st Style, line string) (string, bool)

func Notable(st Style, line string) (string, bool) {
	lower := strings.ToLower(line)
	switch {
	case strings.HasPrefix(lower, "warning:"):
		return st.Paint(st.Icons().Warn, Bold, Yellow) + " " + strings.TrimSpace(line[len("warning:"):]), true
	case strings.HasPrefix(lower, "error:"):
		return st.Paint(st.Icons().Failed, Bold, Red) + " " + strings.TrimSpace(line[len("error:"):]), true
	case strings.Contains(lower, "failed"):
		return st.Paint(line, Red), true
	}
	return "", false
}

func Verbosity(format LineFormat, verbose bool) LineFormat {
	if !verbose {
		return format
	}
	return func(st Style, line string) (string, bool) {
		if out, ok := format(st, line); ok {
			return out, true
		}
		return st.Paint(line, Faint), true
	}
}

type Gutter struct {
	w       io.Writer
	st      Style
	format  LineFormat
	partial []byte
	out     bytes.Buffer
	shown   map[string]bool
	hidden  []string
}

func (p Printer) Gutter(format LineFormat) *Gutter {
	return &Gutter{w: p.W, st: p.Style, format: format, shown: make(map[string]bool)}
}

func (g *Gutter) Write(b []byte) (int, error) {
	g.partial = append(g.partial, b...)
	for {
		i := bytes.IndexByte(g.partial, '\n')
		if i < 0 {
			break
		}
		g.line(string(g.partial[:i]))
		g.partial = g.partial[i+1:]
	}
	if err := g.flush(); err != nil {
		return 0, err
	}
	return len(b), nil
}

func (g *Gutter) Close() error {
	if len(g.partial) > 0 {
		g.line(string(g.partial))
		g.partial = nil
	}
	return g.flush()
}

func (g *Gutter) ShowHidden() error {
	if len(g.hidden) == 0 {
		return nil
	}
	g.emit(g.st.Paint("output:", Bold))
	for _, line := range g.hidden {
		g.emit(g.st.Paint(line, Faint))
	}
	g.hidden = nil
	return g.flush()
}

func (g *Gutter) line(line string) {
	line = strings.TrimRight(line, "\r")
	out, ok := g.format(g.st, line)
	if !ok {
		g.hidden = append(g.hidden, line)
		return
	}
	if g.shown[out] {
		return
	}
	g.shown[out] = true
	g.emit(out)
}

func (g *Gutter) emit(text string) {
	g.out.WriteString(g.st.Paint("│", Gray) + " " + text + "\n")
}

func (g *Gutter) flush() error {
	if g.out.Len() == 0 {
		return nil
	}
	_, err := g.w.Write(g.out.Bytes())
	g.out.Reset()
	if err != nil {
		return fmt.Errorf("writing command output: %w", err)
	}
	return nil
}

func (c Console) RunIndented(ctx context.Context, cmd proc.Cmd, format LineFormat) error {
	g := c.Log().Gutter(format)
	cmd.Stdout, cmd.Stderr = g, g
	runErr := proc.Run(ctx, cmd)
	closeErr := g.Close()
	if runErr != nil {
		closeErr = errors.Join(closeErr, g.ShowHidden())
	}
	return errors.Join(runErr, closeErr)
}
