package nixlog

import (
	"fmt"
	"path"
	"slices"
	"strings"
)

const storeHashLen = 32

type Progress struct {
	Done     int64
	Expected int64
	Running  int64
	Failed   int64
}

type activity struct {
	typ   ActivityType
	name  string
	phase string
}

type Options struct {
	BuildLogs       bool
	OnlyBuildStarts bool
}

type State struct {
	opts       Options
	activities map[uint64]*activity
	running    []uint64
	Builds     Progress
	Copies     Progress
}

func NewState(opts Options) *State {
	return &State{opts: opts, activities: make(map[uint64]*activity)}
}

func (s *State) Apply(e Event) []string {
	switch e.Action {
	case ActionStart:
		return s.start(e)
	case ActionStop:
		s.stop(e.ID)
	case ActionResult:
		return s.result(e)
	case ActionMsg:
		return []string{e.Msg}
	}
	return nil
}

func (s *State) start(e Event) []string {
	typ := ActivityType(e.Type)
	a := &activity{typ: typ, name: activityName(e)}
	s.activities[e.ID] = a
	if typ == ActivityBuild {
		s.running = append(s.running, e.ID)
	}
	if e.Text == "" || e.Level > LevelInfo {
		return nil
	}
	if s.opts.OnlyBuildStarts && typ != ActivityBuild {
		return nil
	}
	return []string{e.Text}
}

func (s *State) stop(id uint64) {
	delete(s.activities, id)
	if i := slices.Index(s.running, id); i >= 0 {
		s.running = slices.Delete(s.running, i, i+1)
	}
}

func (s *State) result(e Event) []string {
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
		}
	case ResultSetPhase:
		if phase, ok := e.StringField(0); ok {
			a.phase = phase
		}
	case ResultBuildLogLine, ResultPostBuildLogLine:
		line, ok := e.StringField(0)
		if !ok || !s.opts.BuildLogs {
			return nil
		}
		return []string{a.name + "> " + line}
	}
	return nil
}

func (s *State) Status() string {
	var parts []string
	if s.Builds.Expected > 0 {
		parts = append(parts, fmt.Sprintf("[built %d/%d]", s.Builds.Done, s.Builds.Expected))
	}
	if s.Copies.Expected > 0 {
		parts = append(parts, fmt.Sprintf("[fetched %d/%d]", s.Copies.Done, s.Copies.Expected))
	}
	if len(s.running) > 0 {
		names := make([]string, 0, len(s.running))
		for _, id := range s.running {
			a := s.activities[id]
			if a.phase != "" {
				names = append(names, fmt.Sprintf("%s (%s)", a.name, a.phase))
				continue
			}
			names = append(names, a.name)
		}
		parts = append(parts, "building "+strings.Join(names, ", "))
	}
	return strings.Join(parts, " ")
}

func activityName(e Event) string {
	p, ok := e.StringField(0)
	if !ok {
		return ""
	}
	return StoreName(p)
}

func StoreName(storePath string) string {
	base := strings.TrimSuffix(path.Base(storePath), ".drv")
	if len(base) > storeHashLen && base[storeHashLen] == '-' {
		return base[storeHashLen+1:]
	}
	return base
}
