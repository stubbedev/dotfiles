package closure

import (
	"cmp"
	"maps"
	"slices"

	"github.com/stubbedev/dotfiles/src/hm/internal/storepath"
)

const minHiddenSizeDelta = 1 << 20

type Status int

const (
	Changed Status = iota + 1
	Upgraded
	Downgraded
	Added
	Removed
)

type group int

const (
	groupChanged group = iota
	groupAdded
	groupRemoved
)

func (s Status) group() group {
	switch s {
	case Added:
		return groupAdded
	case Removed:
		return groupRemoved
	}
	return groupChanged
}

type Selection int

const (
	Unselected Selection = iota
	Selected
	NewlySelected
	NewlyUnselected
)

func selectionOf(wasSelected, isSelected bool) Selection {
	switch {
	case wasSelected && isSelected:
		return Selected
	case isSelected:
		return NewlySelected
	case wasSelected:
		return NewlyUnselected
	}
	return Unselected
}

type versionKey struct {
	version Version
	present bool
}

type amount struct {
	key   versionKey
	count int
}

type changeKind int

const (
	changePair changeKind = iota
	changeAmount
	changeRemoved
	changeAdded
)

type change struct {
	kind changeKind
	old  amount
	new  amount
}

type PackageDiff struct {
	Name      string
	Status    Status
	Selection Selection
	SizeDelta int64
	changes   []change
	omitted   bool
}

func (p PackageDiff) shown(full bool) bool {
	return full || len(p.changes) > 0 || abs(p.SizeDelta) >= minHiddenSizeDelta
}

type Report struct {
	Packages     []PackageDiff
	PathsOld     int
	PathsNew     int
	PathsAdded   int
	PathsRemoved int
	SizeOld      int64
	SizeNew      int64
}

func (r Report) Hidden(full bool) int {
	n := 0
	for _, p := range r.Packages {
		if !p.shown(full) {
			n++
		}
	}
	return n
}

type packageVersions struct {
	old     map[versionKey]int
	new     map[versionKey]int
	oldSize int64
	newSize int64
}

func Diff(oldC, newC Closure) Report {
	r := Report{PathsOld: len(oldC.Sizes), PathsNew: len(newC.Sizes)}
	packages := make(map[string]*packageVersions)
	entry := func(name string) *packageVersions {
		p, ok := packages[name]
		if !ok {
			p = &packageVersions{old: make(map[versionKey]int), new: make(map[versionKey]int)}
			packages[name] = p
		}
		return p
	}
	for path, size := range oldC.Sizes {
		r.SizeOld += size
		if _, ok := newC.Sizes[path]; !ok {
			r.PathsRemoved++
		}
		name, key := packageOf(path)
		p := entry(name)
		p.old[key]++
		p.oldSize += size
	}
	for path, size := range newC.Sizes {
		r.SizeNew += size
		if _, ok := oldC.Sizes[path]; !ok {
			r.PathsAdded++
		}
		name, key := packageOf(path)
		p := entry(name)
		p.new[key]++
		p.newSize += size
	}
	for _, name := range slices.Sorted(maps.Keys(packages)) {
		d, ok := diffPackage(name, packages[name])
		if !ok {
			continue
		}
		d.Selection = selectionOf(oldC.Selected[name], newC.Selected[name])
		r.Packages = append(r.Packages, d)
	}
	slices.SortStableFunc(r.Packages, func(a, b PackageDiff) int {
		return cmp.Or(cmp.Compare(a.Status.group(), b.Status.group()), cmp.Compare(a.Name, b.Name))
	})
	return r
}

func packageOf(path string) (string, versionKey) {
	name, v, ok := storepath.SplitVersion(storepath.Name(path))
	return name, versionKey{version: Version(v), present: ok}
}

func diffPackage(name string, p *packageVersions) (PackageDiff, bool) {
	d := PackageDiff{Name: name, SizeDelta: p.newSize - p.oldSize}
	var removed, added []amount
	for key, oldCount := range p.old {
		newCount, ok := p.new[key]
		switch {
		case !ok:
			removed = append(removed, amount{key: key, count: oldCount})
		case newCount != oldCount:
			d.changes = append(d.changes, change{kind: changeAmount, old: amount{key, oldCount}, new: amount{key, newCount}})
		default:
			d.omitted = true
		}
	}
	for key, newCount := range p.new {
		if _, ok := p.old[key]; !ok {
			added = append(added, amount{key: key, count: newCount})
		}
	}
	if len(removed) == 0 && len(added) == 0 && len(d.changes) == 0 {
		d.Status = Changed
		return d, d.SizeDelta != 0
	}
	slices.SortFunc(d.changes, func(a, b change) int { return compareKeys(a.old.key, b.old.key) })
	slices.SortFunc(removed, compareAmounts)
	slices.SortFunc(added, compareAmounts)
	pairs := min(len(removed), len(added))
	orderings := make(map[ordering]bool)
	var changes []change
	for i := range pairs {
		changes = append(changes, change{kind: changePair, old: removed[i], new: added[i]})
		orderings[pairOrdering(removed[i].key, added[i].key)] = true
	}
	changes = append(changes, d.changes...)
	for _, a := range removed[pairs:] {
		changes = append(changes, change{kind: changeRemoved, old: a})
	}
	for _, a := range added[pairs:] {
		changes = append(changes, change{kind: changeAdded, new: a})
	}
	d.changes = changes
	d.Status = packageStatus(len(p.old) == 0, len(p.new) == 0, orderings)
	return d, true
}

func packageStatus(wasAbsent, isAbsent bool, orderings map[ordering]bool) Status {
	switch {
	case wasAbsent:
		return Added
	case isAbsent:
		return Removed
	case len(orderings) == 1 && orderings[newer]:
		return Upgraded
	case len(orderings) == 1 && orderings[older]:
		return Downgraded
	}
	return Changed
}

func pairOrdering(oldKey, newKey versionKey) ordering {
	if !oldKey.present || !newKey.present {
		return unordered
	}
	return compareVersions(oldKey.version, newKey.version)
}

func compareAmounts(a, b amount) int { return compareKeys(a.key, b.key) }

func compareKeys(a, b versionKey) int {
	if a.present != b.present {
		if a.present {
			return 1
		}
		return -1
	}
	switch compareVersions(a.version, b.version) {
	case newer:
		return -1
	case older:
		return 1
	}
	return cmp.Compare(a.version, b.version)
}

func abs(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}
