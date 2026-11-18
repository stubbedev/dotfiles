package nixlog

import (
	"cmp"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

const (
	barWidth          = 20
	reservedRows      = 2
	minCollapsedChain = 2
)

type View struct {
	Style  ui.Style
	Width  int
	Height int
}

func (s *State) Frame(v View, now time.Time) []string {
	rows := s.tree(v.Style, now)
	if budget := v.Height - reservedRows; len(rows) > budget {
		rows = s.fitRows(v.Style, now, max(budget, 0))
	}
	lines := append(rows, s.legend(v.Style, now, len(rows) > 0))
	for i, line := range lines {
		lines[i] = ui.Truncate(line, v.Width-1)
	}
	return lines
}

func (s *State) Summary(st ui.Style, now time.Time) (string, bool) {
	if s.Builds.Expected == 0 && s.Copies.Expected == 0 {
		return "", false
	}
	ic := st.Icons()
	elapsed := formatDuration(now.Sub(s.started))
	if failed := s.failedBuilds(); failed > 0 {
		return st.Paint(ic.With(ic.Failed, fmt.Sprintf("%d failed build(s) after %s", failed, elapsed)), ui.Bold, ui.Red), true
	}
	var parts []string
	if s.Builds.Done > 0 {
		parts = append(parts, "built "+strconv.FormatInt(s.Builds.Done, 10))
	}
	if s.Copies.Done > 0 {
		parts = append(parts, "fetched "+strconv.FormatInt(s.Copies.Done, 10))
	}
	text := "Finished in " + elapsed
	if len(parts) > 0 {
		text += ": " + strings.Join(parts, ", ")
	}
	return st.Paint(ic.With(ic.Done, text), ui.Green), true
}

func (s *State) failedBuilds() int64 {
	var n int64
	for _, d := range s.drvs {
		if d.Status == Failed {
			n++
		}
	}
	return max(n, s.Builds.Failed)
}

type branch struct {
	ancestors []bool
	last      bool
}

func (b branch) child(last bool) branch {
	return branch{ancestors: append(slices.Clip(b.ancestors), !b.last), last: last}
}

func connectors(st ui.Style, b branch) string {
	var out strings.Builder
	for depth, more := range b.ancestors {
		if more || depth == 0 {
			out.WriteString("│  ")
			continue
		}
		out.WriteString("   ")
	}
	if !b.last || len(b.ancestors) == 0 {
		out.WriteString("├─ ")
	} else {
		out.WriteString("╰─ ")
	}
	return st.Paint(out.String(), ui.Gray)
}

func (s *State) tree(st ui.Style, now time.Time) []string {
	roots, children := s.forest()
	var rows []string
	var walk func(path string, b branch)
	walk = func(path string, b branch) {
		rows = append(rows, connectors(st, b)+s.drvRow(st, s.drvs[path], now))
		kids := children[path]
		if chain := s.waitingChain(kids, children); len(chain) > minCollapsedChain {
			rows = append(rows, connectors(st, b.child(false))+st.Paint(fmt.Sprintf("⋮ %d more", len(chain)-1), ui.Gray))
			kids = chain[len(chain)-1:]
		}
		for i, kid := range kids {
			walk(kid, b.child(i == len(kids)-1))
		}
	}
	for _, root := range roots {
		walk(root, branch{})
	}
	return append(rows, s.transferRows(st, now)...)
}

func (s *State) waitingChain(kids []string, children map[string][]string) []string {
	var chain []string
	for len(kids) == 1 && s.drvs[kids[0]].Status == Planned && len(children[kids[0]]) == 1 {
		chain = append(chain, kids[0])
		kids = children[kids[0]]
	}
	return chain
}

func (s *State) fitRows(st ui.Style, now time.Time, budget int) []string {
	if budget == 0 {
		return nil
	}
	var rows []string
	for _, d := range s.active() {
		rows = append(rows, connectors(st, branch{})+s.drvRow(st, d, now))
	}
	rows = append(rows, s.transferRows(st, now)...)
	if len(rows) <= budget {
		return rows
	}
	hidden := len(rows) - budget + 1
	return append(rows[:budget-1], connectors(st, branch{})+st.Paint(fmt.Sprintf("… and %d more", hidden), ui.Gray))
}

func (s *State) active() []*Derivation {
	var out []*Derivation
	for _, d := range s.drvs {
		if d.Status == Running || d.Status == Failed {
			out = append(out, d)
		}
	}
	slices.SortFunc(out, compareDerivations)
	return out
}

func (s *State) forest() ([]string, map[string][]string) {
	depths := make(map[string]int)
	parents := make(map[string]string)
	children := make(map[string][]*Derivation)
	var roots []*Derivation
	for _, d := range s.active() {
		for node := d; node != nil; {
			if _, seen := parents[node.Path]; seen {
				break
			}
			parent := s.parentOf(node.Path, depths)
			parents[node.Path] = parent
			if parent == "" {
				roots = append(roots, node)
				break
			}
			children[parent] = append(children[parent], node)
			node = s.drvs[parent]
		}
	}
	slices.SortFunc(roots, compareDerivations)
	out := make(map[string][]string, len(children))
	for parent, kids := range children {
		slices.SortFunc(kids, compareDerivations)
		paths := make([]string, len(kids))
		for i, k := range kids {
			paths[i] = k.Path
		}
		out[parent] = paths
	}
	rootPaths := make([]string, len(roots))
	for i, r := range roots {
		rootPaths[i] = r.Path
	}
	return rootPaths, out
}

func (s *State) waitingConsumers(path string) []string {
	var out []string
	for _, c := range s.consumers[path] {
		if d, ok := s.drvs[c]; ok && d.Status == Planned {
			out = append(out, c)
		}
	}
	return out
}

func (s *State) parentOf(path string, depths map[string]int) string {
	best, bestDepth := "", -1
	for _, c := range s.waitingConsumers(path) {
		depth := s.depth(c, depths)
		if depth > bestDepth || (depth == bestDepth && c < best) {
			best, bestDepth = c, depth
		}
	}
	return best
}

func (s *State) depth(path string, memo map[string]int) int {
	if d, ok := memo[path]; ok {
		return d
	}
	depth := 0
	for _, c := range s.waitingConsumers(path) {
		depth = max(depth, s.depth(c, memo)+1)
	}
	memo[path] = depth
	return depth
}

func statusRank(s Status) int {
	switch s {
	case Failed:
		return 0
	case Running:
		return 1
	}
	return 2
}

func compareDerivations(a, b *Derivation) int {
	return cmp.Or(
		cmp.Compare(statusRank(a.Status), statusRank(b.Status)),
		cmp.Compare(a.Name, b.Name),
		cmp.Compare(a.Path, b.Path),
	)
}

func (s *State) drvRow(st ui.Style, d *Derivation, now time.Time) string {
	ic := st.Icons()
	switch d.Status {
	case Running:
		row := st.Paint(ic.Running+ic.Gap, ui.Yellow) + d.Name
		if d.Phase != "" {
			row += "  " + st.Paint(d.Phase, ui.Gray)
		}
		timer := formatDuration(now.Sub(d.Start))
		if d.Estimate > 0 {
			timer += " / " + formatDuration(d.Estimate)
		}
		return row + "  " + st.Paint(ic.With(ic.Clock, timer), ui.Gray)
	case Failed:
		return st.Paint(ic.With(ic.Failed, d.Name), ui.Red)
	}
	return st.Paint(ic.Planned+ic.Gap, ui.Blue) + d.Name
}

func (s *State) transferRows(st ui.Style, now time.Time) []string {
	transfers := make([]*Transfer, 0, len(s.transfers))
	for _, t := range s.transfers {
		transfers = append(transfers, t)
	}
	slices.SortFunc(transfers, func(a, b *Transfer) int {
		return cmp.Or(a.Start.Compare(b.Start), cmp.Compare(a.Name, b.Name))
	})
	ic := st.Icons()
	rows := make([]string, len(transfers))
	for i, t := range transfers {
		row := connectors(st, branch{}) + st.Paint(ic.Download+ic.Gap, ui.Cyan) + t.Name
		if t.Expected > 0 {
			row += "  " + bar(st, t.Done, t.Expected) + "  " + st.Paint(ui.Bytes(t.Done)+" / "+ui.Bytes(t.Expected), ui.Gray)
		}
		rows[i] = row + "  " + st.Paint(ic.With(ic.Clock, formatDuration(now.Sub(t.Start))), ui.Gray)
	}
	return rows
}

func bar(st ui.Style, done, total int64) string {
	filled := int(min(done, total) * barWidth / total)
	return st.Paint(strings.Repeat("━", filled), ui.Cyan) + st.Paint(strings.Repeat("─", barWidth-filled), ui.Gray)
}

func (s *State) legend(st ui.Style, now time.Time, connected bool) string {
	ic := st.Icons()
	corner := "╺━ "
	if connected {
		corner = "┕━ "
	}
	var parts []string
	if b := s.Builds; b.Expected > 0 {
		builds := []string{
			st.Paint(ic.With(ic.Running, strconv.FormatInt(b.Running, 10)), ui.Yellow),
			st.Paint(ic.With(ic.Done, fmt.Sprintf("%d/%d", b.Done, b.Expected)), ui.Green),
		}
		if failed := s.failedBuilds(); failed > 0 {
			builds = append(builds, st.Paint(ic.With(ic.Failed, strconv.FormatInt(failed, 10)), ui.Red))
		}
		builds = append(builds, st.Paint(ic.With(ic.Planned, strconv.FormatInt(b.Waiting(), 10)), ui.Blue))
		parts = append(parts, strings.Join(builds, " "))
	}
	if c := s.Copies; c.Expected > 0 {
		parts = append(parts, st.Paint(ic.With(ic.Download, fmt.Sprintf("%d/%d", c.Done, c.Expected)), ui.Cyan))
	}
	parts = append(parts, st.Paint(ic.With(ic.Clock, formatDuration(now.Sub(s.started))), ui.Gray))
	return st.Paint(corner, ui.Gray) + strings.Join(parts, st.Paint(" │ ", ui.Gray))
}

func formatDuration(d time.Duration) string {
	secs := int64(max(d, 0) / time.Second)
	switch {
	case secs < 60:
		return fmt.Sprintf("%ds", secs)
	case secs < 3600:
		return fmt.Sprintf("%dm%ds", secs/60, secs%60)
	}
	return fmt.Sprintf("%dh%dm", secs/3600, secs%3600/60)
}
