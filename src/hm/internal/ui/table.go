package ui

import (
	"bufio"
	"fmt"
	"io"
	"strings"
)

const columnGap = "  "

type Table struct {
	Header []string
	Rows   [][]string
}

func (t Table) Render(w io.Writer, s Style) error {
	widths := make([]int, len(t.Header))
	for i, h := range t.Header {
		widths[i] = Width(h)
	}
	for r, row := range t.Rows {
		if len(row) != len(t.Header) {
			return fmt.Errorf("rendering a table: row %d has %d cells, want %d", r, len(row), len(t.Header))
		}
		for i, cell := range row {
			widths[i] = max(widths[i], Width(cell))
		}
	}
	bw := bufio.NewWriter(w)
	header := make([]string, len(t.Header))
	for i, h := range t.Header {
		header[i] = s.Paint(h, Bold)
	}
	writeRow(bw, header, widths)
	for _, row := range t.Rows {
		writeRow(bw, row, widths)
	}
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("rendering a table: %w", err)
	}
	return nil
}

func writeRow(w *bufio.Writer, cells []string, widths []int) {
	last := len(cells) - 1
	var line strings.Builder
	for i, cell := range cells {
		if i == last {
			line.WriteString(cell)
			break
		}
		line.WriteString(PadRight(cell, widths[i]))
		line.WriteString(columnGap)
	}
	w.WriteString(strings.TrimRight(line.String(), " "))
	w.WriteByte('\n')
}
