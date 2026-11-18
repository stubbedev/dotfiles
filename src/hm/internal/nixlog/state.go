package nixlog

import (
	"regexp"
	"strings"
	"time"

	"github.com/stubbedev/dotfiles/src/hm/internal/storepath"
	"github.com/stubbedev/dotfiles/src/hm/internal/ui"
)

type Progress struct {
	Done     int64
	Expected int64
	Running  int64
	Failed   int64
}

func (p Progress) Waiting() int64 {
	return max(p.Expected-p.Done-p.Running-p.Failed, 0)
}

type Status int

const (
	Planned Status = iota + 1
	Running
	Done
	Failed
)

type Derivation struct {
	Path     string
	Name     string
	Status   Status
	Phase    string
	Start    time.Time
	Estimate time.Duration
	inputs   []string
}

type Transfer struct {
	Name     string
	Done     int64
	Expected int64
	Start    time.Time
}

type Line struct {
	Prefix string
	Text   string
}

func (l Line) String() string {
	if l.Prefix == "" {
		return l.Text
	}
	return l.Prefix + "> " + l.Text
}

type activity struct {
	typ    ActivityType
	parent uint64
	name   string
	drv    string
}

type planKind int

const (
	planNone planKind = iota
	planBuild
	planFetch
)

var (
	buildPlanHeader = regexp.MustCompile(`^(?:these \d+ derivations|this derivation) will be built:$`)
	fetchPlanHeader = regexp.MustCompile(`^(?:these \d+ paths|this path) will be fetched`)
	failedBuild     = regexp.MustCompile(`(?:Cannot build|builder for) '(/nix/store/[^']+\.drv)'`)
)

type Options struct {
	BuildLogs bool
	Live      bool
	Inputs    func(drvPath string) ([]string, error)
	Estimates map[string]time.Duration
}

type State struct {
	opts       Options
	started    time.Time
	activities map[uint64]*activity
	drvs       map[string]*Derivation
	consumers  map[string][]string
	transfers  map[uint64]*Transfer
	measured   map[string]time.Duration
	plan       planKind
	Builds     Progress
	Copies     Progress
}

func NewState(opts Options, started time.Time) *State {
	return &State{
		opts:       opts,
		started:    started,
		activities: make(map[uint64]*activity),
		drvs:       make(map[string]*Derivation),
		consumers:  make(map[string][]string),
		transfers:  make(map[uint64]*Transfer),
		measured:   make(map[string]time.Duration),
	}
}

func (s *State) Apply(e Event, now time.Time) ([]Line, error) {
	switch e.Action {
	case ActionStart:
		return s.start(e, now)
	case ActionStop:
		s.stop(e.ID, now)
	case ActionResult:
		return s.result(e), nil
	case ActionMsg:
		return s.msg(e)
	}
	return nil, nil
}

func (s *State) msg(e Event) ([]Line, error) {
	text := ui.Strip(e.Msg)
	if m := failedBuild.FindStringSubmatch(text); m != nil {
		if d, ok := s.drvs[m[1]]; ok {
			d.Status = Failed
		}
	}
	if e.Level > LevelInfo {
		return []Line{{Text: e.Msg}}, nil
	}
	switch {
	case buildPlanHeader.MatchString(text):
		s.plan = planBuild
	case fetchPlanHeader.MatchString(text):
		s.plan = planFetch
	case s.plan != planNone && strings.HasPrefix(text, "  /nix/store/"):
		if s.plan == planBuild {
			if _, err := s.derivation(strings.TrimSpace(text)); err != nil {
				return nil, err
			}
		}
	default:
		s.plan = planNone
		return []Line{{Text: e.Msg}}, nil
	}
	if s.opts.Live {
		return nil, nil
	}
	return []Line{{Text: e.Msg}}, nil
}

func (s *State) derivation(drvPath string) (*Derivation, error) {
	if d, ok := s.drvs[drvPath]; ok {
		return d, nil
	}
	var inputs []string
	if s.opts.Inputs != nil {
		var err error
		if inputs, err = s.opts.Inputs(drvPath); err != nil {
			return nil, err
		}
	}
	d := &Derivation{
		Path:     drvPath,
		Name:     storepath.Name(drvPath),
		Status:   Planned,
		Estimate: s.opts.Estimates[storepath.Package(drvPath)],
		inputs:   inputs,
	}
	s.drvs[drvPath] = d
	for _, in := range inputs {
		s.consumers[in] = append(s.consumers[in], drvPath)
	}
	return d, nil
}

func (s *State) start(e Event, now time.Time) ([]Line, error) {
	typ := ActivityType(e.Type)
	a := &activity{typ: typ, parent: e.Parent, name: activityName(e)}
	s.activities[e.ID] = a
	switch typ {
	case ActivityBuild:
		drvPath, _ := e.StringField(0)
		d, err := s.derivation(drvPath)
		if err != nil {
			return nil, err
		}
		a.drv = drvPath
		d.Status, d.Start, d.Phase = Running, now, ""
	case ActivityCopyPath:
		s.transfers[e.ID] = &Transfer{Name: a.name, Start: now}
	}
	if s.opts.Live || e.Text == "" || e.Level > LevelInfo {
		return nil, nil
	}
	return []Line{{Text: e.Text}}, nil
}

func (s *State) stop(id uint64, now time.Time) {
	a, ok := s.activities[id]
	if !ok {
		return
	}
	delete(s.activities, id)
	delete(s.transfers, id)
	if a.drv == "" {
		return
	}
	if d := s.drvs[a.drv]; d.Status == Running {
		d.Status = Done
		s.measured[storepath.Package(d.Path)] = now.Sub(d.Start)
	}
}

func (s *State) result(e Event) []Line {
	a, ok := s.activities[e.ID]
	if !ok {
		return nil
	}
	switch ResultType(e.Type) {
	case ResultProgress:
		p := Progress{}
		p.Done, _ = e.IntField(0)
		p.Expected, _ = e.IntField(1)
		p.Running, _ = e.IntField(2)
		p.Failed, _ = e.IntField(3)
		switch a.typ {
		case ActivityBuilds:
			s.Builds = p
		case ActivityCopyPaths:
			s.Copies = p
		case ActivityFileTransfer:
			if t := s.transferOf(a); t != nil {
				t.Done, t.Expected = p.Done, p.Expected
			}
		}
	case ResultSetPhase:
		if phase, ok := e.StringField(0); ok && a.drv != "" {
			s.drvs[a.drv].Phase = phase
		}
	case ResultBuildLogLine, ResultPostBuildLogLine:
		line, ok := e.StringField(0)
		if !ok || !s.opts.BuildLogs {
			return nil
		}
		return []Line{{Prefix: a.name, Text: line}}
	}
	return nil
}

func (s *State) transferOf(a *activity) *Transfer {
	for id := a.parent; id != 0; {
		if t, ok := s.transfers[id]; ok {
			return t
		}
		parent, ok := s.activities[id]
		if !ok {
			return nil
		}
		id = parent.parent
	}
	return nil
}

func (s *State) Measured() map[string]time.Duration { return s.measured }

func activityName(e Event) string {
	p, ok := e.StringField(0)
	if !ok {
		return ""
	}
	return storepath.Name(p)
}
