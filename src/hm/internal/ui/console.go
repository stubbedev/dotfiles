package ui

import (
	"fmt"
	"io"

	"github.com/stubbedev/dotfiles/src/hm/internal/proc"
)

type Size struct {
	Width  int
	Height int
}

type Console struct {
	proc.Streams
	OutStyle Style
	ErrStyle Style
}

func (c Console) Out() Printer { return Printer{W: c.Stdout, Style: c.OutStyle} }

func (c Console) Log() Printer { return Printer{W: c.Stderr, Style: c.ErrStyle} }

type Printer struct {
	W     io.Writer
	Style Style
}

type Mark int

const (
	MarkStep Mark = iota + 1
	MarkWarn
	MarkDone
	MarkAsk
	MarkError
)

func (p Printer) Mark(m Mark) string {
	switch m {
	case MarkStep:
		return p.Style.Paint(">", Bold, Green)
	case MarkWarn:
		return p.Style.Paint("!", Bold, Yellow)
	case MarkDone:
		return p.Style.Paint(p.Style.Icons().Done, Bold, Green)
	case MarkAsk:
		return p.Style.Paint("?", Bold, Cyan)
	}
	return p.Style.Paint("error:", Bold, Red)
}

func (p Printer) Step(format string, args ...any) { p.line(MarkStep, format, args...) }

func (p Printer) Warn(format string, args ...any) { p.line(MarkWarn, format, args...) }

func (p Printer) Done(format string, args ...any) { p.line(MarkDone, format, args...) }

func (p Printer) Error(err error) { p.line(MarkError, "%v", err) }

func (p Printer) line(m Mark, format string, args ...any) {
	fmt.Fprintln(p.W, p.Mark(m)+" "+fmt.Sprintf(format, args...))
}
