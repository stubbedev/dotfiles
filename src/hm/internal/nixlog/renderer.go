package nixlog

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"unicode/utf8"
)

const clearLine = "\r\x1b[K"

type Renderer struct {
	w        io.Writer
	width    int
	state    *State
	status   string
	firstErr error
}

func NewRenderer(w io.Writer, ttyWidth int, buildLogs bool) *Renderer {
	return &Renderer{
		w:     w,
		width: ttyWidth,
		state: NewState(Options{BuildLogs: buildLogs, OnlyBuildStarts: ttyWidth > 0}),
	}
}

func (r *Renderer) Consume(in io.Reader) error {
	br := bufio.NewReader(in)
	for {
		line, err := br.ReadBytes('\n')
		if len(line) > 0 {
			r.handle(trimNewline(line))
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			r.clearStatus()
			return fmt.Errorf("reading nix log stream: %w", err)
		}
	}
	r.clearStatus()
	return r.firstErr
}

func (r *Renderer) handle(line []byte) {
	ev, ok, err := Parse(line)
	if err != nil && r.firstErr == nil {
		r.firstErr = err
	}
	if !ok || err != nil {
		r.print(string(line))
		return
	}
	for _, out := range r.state.Apply(ev) {
		r.print(out)
	}
	r.drawStatus()
}

func (r *Renderer) print(line string) {
	r.clearStatus()
	fmt.Fprintln(r.w, line)
}

func (r *Renderer) drawStatus() {
	if r.width <= 0 {
		return
	}
	status := truncate(r.state.Status(), r.width-1)
	if status == r.status {
		return
	}
	fmt.Fprint(r.w, clearLine+status)
	r.status = status
}

func (r *Renderer) clearStatus() {
	if r.status == "" {
		return
	}
	fmt.Fprint(r.w, clearLine)
	r.status = ""
}

func truncate(s string, width int) string {
	if width <= 0 {
		return ""
	}
	if utf8.RuneCountInString(s) <= width {
		return s
	}
	runes := []rune(s)
	return string(runes[:width-1]) + "…"
}

func trimNewline(line []byte) []byte {
	if n := len(line); n > 0 && line[n-1] == '\n' {
		return line[:n-1]
	}
	return line
}
