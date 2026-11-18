package closure

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	sizeDeltaThreshold = 8 << 10
	hashLikeMinLen     = 20
)

type RenderOptions struct {
	Full     bool
	FullFlag string
}

func Render(w io.Writer, st ui.Style, r Report, opts RenderOptions) error {
	bw := bufio.NewWriter(w)
	bw.WriteByte('\n')
	shown := r.renderPackages(bw, st, opts.Full)
	if shown > 0 {
		bw.WriteByte('\n')
	}
	renderPathStats(bw, st, r)
	renderSize(bw, st, r.SizeOld, r.SizeNew)
	if hidden := r.Hidden(opts.Full); hidden > 0 {
		fmt.Fprintf(bw, "\n%s: %s hidden %s\n", st.Paint("NOTE", ui.Bold), st.Paint(strconv.Itoa(hidden), ui.Yellow),
			st.Paint("(size-only changes under "+ui.Bytes(minHiddenSizeDelta)+", "+opts.FullFlag+" to show)", ui.Faint))
	}
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("writing the closure diff: %w", err)
	}
	return nil
}

func (r Report) renderPackages(w *bufio.Writer, st ui.Style, full bool) int {
	nameWidth := 0
	for _, p := range r.Packages {
		if p.shown(full) {
			nameWidth = max(nameWidth, len(p.Name))
		}
	}
	nameWidth++
	total := 0
	for start := 0; start < len(r.Packages); {
		g := r.Packages[start].Status.group()
		end := start
		var shown []PackageDiff
		for ; end < len(r.Packages) && r.Packages[end].Status.group() == g; end++ {
			if r.Packages[end].shown(full) {
				shown = append(shown, r.Packages[end])
			}
		}
		start = end
		if len(shown) == 0 {
			continue
		}
		if total > 0 {
			w.WriteByte('\n')
		}
		total += len(shown)
		fmt.Fprintf(w, "%s %s\n", st.Paint(groupTitle(g), ui.Bold), st.Paint("("+strconv.Itoa(len(shown))+")", ui.Faint))
		for _, p := range shown {
			renderPackage(w, st, p, nameWidth)
		}
	}
	return total
}

func groupTitle(g group) string {
	switch g {
	case groupAdded:
		return "ADDED"
	case groupRemoved:
		return "REMOVED"
	}
	return "CHANGED"
}

func renderPackage(w *bufio.Writer, st ui.Style, p PackageDiff, nameWidth int) {
	name := p.Name
	if p.Selection == Unselected || p.Selection == NewlyUnselected {
		name = st.Paint(name, ui.Faint)
	}
	fmt.Fprintf(w, "[%s%s] %s", statusChar(st, p.Status), selectionChar(st, p.Selection), name)
	oldText, newText := versionTexts(st, p)
	arrow := ""
	if oldText != "" && newText != "" {
		arrow = " -> "
	}
	var details []string
	if versions := oldText + arrow + newText; versions != "" {
		details = append(details, versions)
	}
	if size := sizeDelta(st, p.SizeDelta); size != "" {
		details = append(details, size)
	}
	if len(details) > 0 {
		w.WriteString(strings.Repeat(" ", nameWidth-len(p.Name)) + strings.Join(details, ", "))
	}
	w.WriteByte('\n')
}

func statusChar(st ui.Style, s Status) string {
	switch s {
	case Upgraded:
		return st.Paint("U", ui.Bold, ui.BrightCyan)
	case Downgraded:
		return st.Paint("D", ui.Bold, ui.Magenta)
	case Added:
		return st.Paint("A", ui.Bold, ui.Green)
	case Removed:
		return st.Paint("R", ui.Bold, ui.Red)
	}
	return st.Paint("C", ui.Bold, ui.Yellow)
}

func selectionChar(st ui.Style, s Selection) string {
	switch s {
	case Selected:
		return st.Paint("*", ui.Bold)
	case NewlySelected:
		return st.Paint("+", ui.Bold)
	case NewlyUnselected:
		return "-"
	}
	return "."
}

func sizeDelta(st ui.Style, delta int64) string {
	switch {
	case abs(delta) <= sizeDeltaThreshold:
		return ""
	case delta > 0:
		return st.Paint("+"+ui.Bytes(delta), ui.BrightCyan)
	}
	return st.Paint(ui.Bytes(delta), ui.Magenta)
}

type versionWriter []*strings.Builder

func (v *versionWriter) next() *strings.Builder {
	b := new(strings.Builder)
	*v = append(*v, b)
	return b
}

func (v versionWriter) String() string {
	parts := make([]string, len(v))
	for i, b := range v {
		parts[i] = b.String()
	}
	return strings.Join(parts, ", ")
}

func versionTexts(st ui.Style, p PackageDiff) (string, string) {
	var oldW, newW versionWriter
	for _, c := range p.changes {
		switch c.kind {
		case changeRemoved:
			writeAmount(oldW.next(), st, c.old, ui.Red)
		case changeAdded:
			writeAmount(newW.next(), st, c.new, ui.Green)
		case changeAmount:
			ob, nb := oldW.next(), newW.next()
			writeVersion(ob, st, c.old.key, ui.Yellow)
			writeVersion(nb, st, c.new.key, ui.Yellow)
			writeCount(ob, st, c.old.count, ui.Red)
			writeCount(nb, st, c.new.count, ui.Green)
		case changePair:
			ob, nb := oldW.next(), newW.next()
			if c.old.key.present && c.new.key.present {
				writeVersionDiff(ob, nb, st, c.old.key.version, c.new.key.version)
			} else {
				writeVersion(ob, st, c.old.key, ui.Red)
				writeVersion(nb, st, c.new.key, ui.Green)
			}
			writePairCounts(ob, nb, st, c.old.count, c.new.count)
		}
	}
	if p.omitted && len(p.changes) > 0 {
		unchanged := st.Paint("<unchanged>", ui.Blue, ui.Italic)
		oldW.next().WriteString(unchanged)
		newW.next().WriteString(unchanged)
	}
	return oldW.String(), newW.String()
}

func writeAmount(b *strings.Builder, st ui.Style, a amount, color ui.Attr) {
	writeVersion(b, st, a.key, color)
	writeCount(b, st, a.count, color)
}

func writeVersion(b *strings.Builder, st ui.Style, key versionKey, color ui.Attr) {
	if !key.present {
		b.WriteString(st.Paint("<none>", color))
		return
	}
	for _, p := range key.version.pieces() {
		if p.separator {
			b.WriteString(p.text)
			continue
		}
		b.WriteString(st.Paint(p.text, color))
	}
}

func writeCount(b *strings.Builder, st ui.Style, count int, color ui.Attr) {
	if count > 1 {
		b.WriteString(" ×" + st.Paint(strconv.Itoa(count), color))
	}
}

func writePairCounts(ob, nb *strings.Builder, st ui.Style, oldCount, newCount int) {
	if oldCount == newCount {
		writeCount(ob, st, oldCount, ui.Yellow)
		writeCount(nb, st, newCount, ui.Yellow)
		return
	}
	writeCount(ob, st, oldCount, ui.Red)
	writeCount(nb, st, newCount, ui.Green)
}

func writeVersionDiff(ob, nb *strings.Builder, st ui.Style, oldV, newV Version) {
	oldP, newP := oldV.pieces(), newV.pieces()
	prefix := 0
	for prefix < len(oldP) && prefix < len(newP) && oldP[prefix] == newP[prefix] {
		prefix++
	}
	suffix := 0
	for suffix < len(oldP)-prefix && suffix < len(newP)-prefix && oldP[len(oldP)-1-suffix] == newP[len(newP)-1-suffix] {
		suffix++
	}
	writePieces(ob, st, oldP[:prefix], ui.Yellow)
	writePieces(nb, st, newP[:prefix], ui.Yellow)
	oldMid, newMid := oldP[prefix:len(oldP)-suffix], newP[prefix:len(newP)-suffix]
	for i := range max(len(oldMid), len(newMid)) {
		switch {
		case i >= len(newMid):
			writePieces(ob, st, oldMid[i:i+1], ui.Red)
		case i >= len(oldMid):
			writePieces(nb, st, newMid[i:i+1], ui.Green)
		default:
			writePiecePair(ob, nb, st, oldMid[i], newMid[i])
		}
	}
	writePieces(ob, st, oldP[len(oldP)-suffix:], ui.Yellow)
	writePieces(nb, st, newP[len(newP)-suffix:], ui.Yellow)
}

func writePieces(b *strings.Builder, st ui.Style, pieces []piece, color ui.Attr) {
	for _, p := range pieces {
		if p.separator {
			b.WriteString(p.text)
			continue
		}
		b.WriteString(st.Paint(p.text, color))
	}
}

func writePiecePair(ob, nb *strings.Builder, st ui.Style, oldP, newP piece) {
	if oldP == newP {
		writePieces(ob, st, []piece{oldP}, ui.Yellow)
		writePieces(nb, st, []piece{newP}, ui.Yellow)
		return
	}
	if oldP.separator || newP.separator || (len(oldP.text) > hashLikeMinLen && len(newP.text) > hashLikeMinLen && noCommonPosition(oldP.text, newP.text)) {
		writePieces(ob, st, []piece{oldP}, ui.Red)
		writePieces(nb, st, []piece{newP}, ui.Green)
		return
	}
	var oldRun, newRun colorRun
	diverged := false
	for _, op := range charDiff([]rune(oldP.text), []rune(newP.text)) {
		switch op.kind {
		case opBoth:
			if diverged {
				oldRun.add(ob, st, op.r, ui.Red)
				newRun.add(nb, st, op.r, ui.Green)
				continue
			}
			oldRun.add(ob, st, op.r, ui.Yellow)
			newRun.add(nb, st, op.r, ui.Yellow)
		case opOld:
			diverged = true
			oldRun.add(ob, st, op.r, ui.Red)
		case opNew:
			diverged = true
			newRun.add(nb, st, op.r, ui.Green)
		}
	}
	oldRun.flush(ob, st)
	newRun.flush(nb, st)
}

type colorRun struct {
	color ui.Attr
	text  []rune
}

func (c *colorRun) add(b *strings.Builder, st ui.Style, r rune, color ui.Attr) {
	if color != c.color {
		c.flush(b, st)
		c.color = color
	}
	c.text = append(c.text, r)
}

func (c *colorRun) flush(b *strings.Builder, st ui.Style) {
	if len(c.text) > 0 {
		b.WriteString(st.Paint(string(c.text), c.color))
		c.text = c.text[:0]
	}
}

func noCommonPosition(a, b string) bool {
	for i := range min(len(a), len(b)) {
		if a[i] == b[i] {
			return false
		}
	}
	return true
}

type opKind int

const (
	opBoth opKind = iota
	opOld
	opNew
)

type diffOp struct {
	kind opKind
	r    rune
}

func charDiff(a, b []rune) []diffOp {
	lcs := make([][]int, len(a)+1)
	for i := range lcs {
		lcs[i] = make([]int, len(b)+1)
	}
	for i := len(a) - 1; i >= 0; i-- {
		for j := len(b) - 1; j >= 0; j-- {
			if a[i] == b[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else {
				lcs[i][j] = max(lcs[i+1][j], lcs[i][j+1])
			}
		}
	}
	ops := make([]diffOp, 0, len(a)+len(b))
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		switch {
		case a[i] == b[j]:
			ops = append(ops, diffOp{opBoth, a[i]})
			i++
			j++
		case lcs[i+1][j] >= lcs[i][j+1]:
			ops = append(ops, diffOp{opOld, a[i]})
			i++
		default:
			ops = append(ops, diffOp{opNew, b[j]})
			j++
		}
	}
	for ; i < len(a); i++ {
		ops = append(ops, diffOp{opOld, a[i]})
	}
	for ; j < len(b); j++ {
		ops = append(ops, diffOp{opNew, b[j]})
	}
	return ops
}

func renderPathStats(w *bufio.Writer, st ui.Style, r Report) {
	fmt.Fprintf(w, "%s: %s -> %s (%s, %s)\n", st.Paint("PATHS", ui.Bold),
		st.Paint(strconv.Itoa(r.PathsOld), ui.Red), st.Paint(strconv.Itoa(r.PathsNew), ui.Green),
		st.Paint("+"+strconv.Itoa(r.PathsAdded), ui.Green), st.Paint("-"+strconv.Itoa(r.PathsRemoved), ui.Red))
}

func renderSize(w *bufio.Writer, st ui.Style, oldSize, newSize int64) {
	delta := newSize - oldSize
	var deltaText string
	switch {
	case delta > 0:
		deltaText = "+" + st.Paint(ui.Bytes(delta), ui.Green)
	case delta < 0:
		deltaText = st.Paint(ui.Bytes(delta), ui.Red)
	default:
		deltaText = ui.Bytes(0)
	}
	fmt.Fprintf(w, "%s: %s -> %s (%s)\n", st.Paint("SIZE", ui.Bold),
		st.Paint(ui.Bytes(oldSize), ui.Red), st.Paint(ui.Bytes(newSize), ui.Green), deltaText)
}
