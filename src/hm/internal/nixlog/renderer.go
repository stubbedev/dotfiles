package nixlog

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	frameInterval = 100 * time.Millisecond
	drainLimit    = 256
	hideCursor    = "\x1b[?25l"
	showCursor    = "\x1b[?25h"
	clearToEnd    = "\x1b[J"
)

type Config struct {
	Style     ui.Style
	Width     int
	Height    int
	Resize    <-chan ui.Size
	BuildLogs bool
	Inputs    func(drvPath string) ([]string, error)
	Estimates map[string]time.Duration
	Now       func() time.Time
}

type Renderer struct {
	w        io.Writer
	cfg      Config
	state    *State
	widths   []int
	frame    string
	buf      bytes.Buffer
	firstErr error
}

func NewRenderer(w io.Writer, cfg Config) *Renderer {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	return &Renderer{
		w:     w,
		cfg:   cfg,
		state: NewState(Options{BuildLogs: cfg.BuildLogs, Live: cfg.live(), Inputs: cfg.Inputs, Estimates: cfg.Estimates}, cfg.Now()),
	}
}

func (c Config) live() bool { return c.Width > 0 }

func (c Config) view() View { return View{Style: c.Style, Width: c.Width, Height: c.Height} }

func (r *Renderer) Consume(in io.Reader) error {
	if !r.cfg.live() {
		return r.consumePlain(in)
	}
	return r.consumeLive(in)
}

func (r *Renderer) consumePlain(in io.Reader) error {
	br := bufio.NewReader(in)
	for {
		line, err := br.ReadBytes('\n')
		if len(line) > 0 {
			r.handle(trimNewline(line))
			r.flush()
		}
		if errors.Is(err, io.EOF) {
			return r.firstErr
		}
		if err != nil {
			return fmt.Errorf("reading nix log stream: %w", err)
		}
	}
}

type readResult struct {
	line []byte
	err  error
}

func readLines(in io.Reader, out chan<- readResult) {
	defer close(out)
	br := bufio.NewReader(in)
	for {
		line, err := br.ReadBytes('\n')
		if len(line) > 0 {
			out <- readResult{line: trimNewline(line)}
		}
		if errors.Is(err, io.EOF) {
			return
		}
		if err != nil {
			out <- readResult{err: fmt.Errorf("reading nix log stream: %w", err)}
			return
		}
	}
}

func (r *Renderer) consumeLive(in io.Reader) error {
	lines := make(chan readResult, drainLimit)
	go readLines(in, lines)
	ticker := time.NewTicker(frameInterval)
	defer ticker.Stop()
	r.buf.WriteString(hideCursor)
	var readErr error
	for open := true; open; {
		select {
		case res, ok := <-lines:
			if !ok {
				open = false
				break
			}
			var err error
			open, err = r.applyBatch(res, lines)
			readErr = firstError(readErr, err)
		case size := <-r.cfg.Resize:
			r.resize(size)
		case <-ticker.C:
		}
		if open {
			r.redraw()
		}
		r.flush()
	}
	r.clearFrame()
	if summary, ok := r.state.Summary(r.cfg.Style, r.cfg.Now()); ok {
		r.buf.WriteString(summary + "\n")
	}
	r.buf.WriteString(showCursor)
	r.flush()
	return firstError(readErr, r.firstErr)
}

func (r *Renderer) Measured() map[string]time.Duration { return r.state.Measured() }

func (r *Renderer) resize(size ui.Size) {
	if size.Width <= 0 {
		return
	}
	r.cfg.Width, r.cfg.Height = size.Width, size.Height
	r.frame = ""
}

func (r *Renderer) applyBatch(first readResult, lines <-chan readResult) (bool, error) {
	err := r.handleResult(first)
	for range drainLimit {
		select {
		case res, ok := <-lines:
			if !ok {
				return false, err
			}
			err = firstError(err, r.handleResult(res))
		default:
			return true, err
		}
	}
	return true, err
}

func firstError(first, next error) error {
	if first != nil {
		return first
	}
	return next
}

func (r *Renderer) handleResult(res readResult) error {
	if res.err != nil {
		return res.err
	}
	r.handle(res.line)
	return nil
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
	out, err := r.state.Apply(ev, r.cfg.Now())
	if err != nil && r.firstErr == nil {
		r.firstErr = err
	}
	for _, l := range out {
		r.print(r.format(l))
	}
}

func (r *Renderer) format(l Line) string {
	if l.Prefix == "" || !r.cfg.live() {
		return l.String()
	}
	return r.cfg.Style.Paint(l.Prefix+">", ui.Blue) + " " + l.Text
}

func (r *Renderer) print(line string) {
	r.clearFrame()
	r.buf.WriteString(line)
	r.buf.WriteByte('\n')
}

func (r *Renderer) redraw() {
	lines := r.state.Frame(r.cfg.view(), r.cfg.Now())
	frame := strings.Join(lines, "\n")
	if len(r.widths) > 0 && frame == r.frame {
		return
	}
	r.clearFrame()
	r.buf.WriteString(frame)
	r.frame = frame
	r.widths = r.widths[:0]
	for _, line := range lines {
		r.widths = append(r.widths, ui.Width(line))
	}
}

func (r *Renderer) clearFrame() {
	if len(r.widths) == 0 {
		return
	}
	rows := screenRows(r.widths, r.cfg.Width)
	r.buf.WriteByte('\r')
	if rows > 1 {
		r.buf.WriteString("\x1b[" + strconv.Itoa(rows-1) + "A")
	}
	r.buf.WriteString(clearToEnd)
	r.widths = r.widths[:0]
}

func screenRows(widths []int, termWidth int) int {
	rows := 0
	for _, w := range widths {
		rows += max(1, (w+termWidth-1)/termWidth)
	}
	return rows
}

func (r *Renderer) flush() {
	if r.buf.Len() == 0 {
		return
	}
	if _, err := r.w.Write(r.buf.Bytes()); err != nil && r.firstErr == nil {
		r.firstErr = fmt.Errorf("writing build progress: %w", err)
	}
	r.buf.Reset()
}

func trimNewline(line []byte) []byte {
	if n := len(line); n > 0 && line[n-1] == '\n' {
		return line[:n-1]
	}
	return line
}
