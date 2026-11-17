package nixlog

import (
	"bytes"
	"encoding/json"
	"fmt"
)

const linePrefix = "@nix "

type Action int

const (
	ActionStart Action = iota + 1
	ActionStop
	ActionResult
	ActionMsg
)

type ActivityType int

const (
	ActivityCopyPath      ActivityType = 100
	ActivityFileTransfer  ActivityType = 101
	ActivityRealise       ActivityType = 102
	ActivityCopyPaths     ActivityType = 103
	ActivityBuilds        ActivityType = 104
	ActivityBuild         ActivityType = 105
	ActivitySubstitute    ActivityType = 108
	ActivityPostBuildHook ActivityType = 110
)

type ResultType int

const (
	ResultBuildLogLine     ResultType = 101
	ResultSetPhase         ResultType = 104
	ResultProgress         ResultType = 105
	ResultPostBuildLogLine ResultType = 107
)

type Level int

const LevelInfo Level = 3

type Event struct {
	Action Action
	ID     uint64
	Parent uint64
	Level  Level
	Type   int
	Text   string
	Msg    string
	Fields []any
}

type wireEvent struct {
	Action string `json:"action"`
	ID     uint64 `json:"id"`
	Parent uint64 `json:"parent"`
	Level  int    `json:"level"`
	Type   int    `json:"type"`
	Text   string `json:"text"`
	Msg    string `json:"msg"`
	Fields []any  `json:"fields"`
}

var actions = map[string]Action{
	"start":  ActionStart,
	"stop":   ActionStop,
	"result": ActionResult,
	"msg":    ActionMsg,
}

func Parse(line []byte) (Event, bool, error) {
	payload, ok := bytes.CutPrefix(line, []byte(linePrefix))
	if !ok {
		return Event{}, false, nil
	}
	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.UseNumber()
	var w wireEvent
	if err := dec.Decode(&w); err != nil {
		return Event{}, true, fmt.Errorf("decoding nix log event %q: %w", payload, err)
	}
	action, ok := actions[w.Action]
	if !ok {
		return Event{}, true, fmt.Errorf("decoding nix log event %q: unknown action %q", payload, w.Action)
	}
	return Event{
		Action: action,
		ID:     w.ID,
		Parent: w.Parent,
		Level:  Level(w.Level),
		Type:   w.Type,
		Text:   w.Text,
		Msg:    w.Msg,
		Fields: w.Fields,
	}, true, nil
}

func (e Event) StringField(i int) (string, bool) {
	if i >= len(e.Fields) {
		return "", false
	}
	s, ok := e.Fields[i].(string)
	return s, ok
}

func (e Event) IntField(i int) (int64, bool) {
	if i >= len(e.Fields) {
		return 0, false
	}
	n, ok := e.Fields[i].(json.Number)
	if !ok {
		return 0, false
	}
	v, err := n.Int64()
	return v, err == nil
}
