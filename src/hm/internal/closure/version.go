package closure

import (
	"cmp"
	"strings"
	"unicode/utf8"

	"github.com/stubbedev/dotfiles/src/hm/internal/storepath"
)

const separators = ".-_+*=× "

var preReleaseMarkers = []string{"alpha", "beta", "pre", "rc"}

type Version string

type piece struct {
	text      string
	separator bool
}

func (v Version) pieces() []piece {
	var out []piece
	rest := string(v)
	for rest != "" {
		i := strings.IndexAny(rest, separators)
		switch {
		case i == 0:
			_, size := utf8.DecodeRuneInString(rest)
			out = append(out, piece{text: rest[:size], separator: true})
			rest = rest[size:]
		case i < 0:
			out = append(out, piece{text: rest})
			rest = ""
		default:
			out = append(out, piece{text: rest[:i]})
			rest = rest[i:]
		}
	}
	return out
}

func (v Version) components() []string {
	var out []string
	for _, p := range v.pieces() {
		if !p.separator {
			out = append(out, p.text)
		}
	}
	return out
}

type ordering int

const (
	unordered ordering = iota
	older
	same
	newer
)

func compareVersions(oldV, newV Version) ordering {
	a, b := oldV.components(), newV.components()
	for i := range max(len(a), len(b)) {
		ca, okA := at(a, i)
		cb, okB := at(b, i)
		if okA && okB && ca == cb {
			continue
		}
		if !okA || !okB {
			return toOrdering(cmp.Compare(rank(i, ca, okA), rank(i, cb, okB)))
		}
		if storepath.IsHex(ca) && storepath.IsHex(cb) && (storepath.HasHexLetter(ca) || storepath.HasHexLetter(cb)) {
			return unordered
		}
		if c := cmp.Or(cmp.Compare(rank(i, ca, true), rank(i, cb, true)), compareSegments(ca, cb)); c != 0 {
			return toOrdering(c)
		}
	}
	return same
}

func at(s []string, i int) (string, bool) {
	if i < len(s) {
		return s[i], true
	}
	return "", false
}

func toOrdering(c int) ordering {
	switch {
	case c < 0:
		return newer
	case c > 0:
		return older
	}
	return same
}

func rank(index int, component string, present bool) int {
	switch {
	case !present && index == 0:
		return 0
	case !present:
		return 2
	case index > 0 && isPreRelease(component):
		return 1
	}
	return 3
}

func isPreRelease(component string) bool {
	lower := strings.ToLower(component)
	for _, m := range preReleaseMarkers {
		if strings.HasPrefix(lower, m) {
			return true
		}
	}
	return false
}

func segments(component string) []string {
	var out []string
	start := 0
	for i := 1; i <= len(component); i++ {
		if i == len(component) || storepath.IsDigit(component[i]) != storepath.IsDigit(component[i-1]) {
			out = append(out, component[start:i])
			start = i
		}
	}
	return out
}

func compareSegments(a, b string) int {
	sa, sb := segments(a), segments(b)
	shared := min(len(sa), len(sb))
	for i := range shared {
		if c := compareSegment(sa[i], sb[i]); c != 0 {
			return c
		}
	}
	switch {
	case len(sa) > shared && isPreRelease(sa[shared]):
		return -1
	case len(sb) > shared && isPreRelease(sb[shared]):
		return 1
	}
	return cmp.Compare(len(sa), len(sb))
}

func compareSegment(a, b string) int {
	da, db := storepath.IsDigit(a[0]), storepath.IsDigit(b[0])
	switch {
	case da && db:
		a, b = strings.TrimLeft(a, "0"), strings.TrimLeft(b, "0")
		return cmp.Or(cmp.Compare(len(a), len(b)), cmp.Compare(a, b))
	case da:
		return -1
	case db:
		return 1
	}
	return cmp.Compare(strings.ToLower(a), strings.ToLower(b))
}
