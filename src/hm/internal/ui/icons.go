package ui

import "strings"

type Icons struct {
	Step     string
	Build    string
	Diff     string
	Activate string
	Hook     string
	Warn     string
	Stop     string
	Restart  string
	Reload   string
	Start    string
	Running  string
	Done     string
	Planned  string
	Failed   string
	Download string
	Upload   string
	Clock    string
	Summary  string
	Gap      string
}

var Unicode = Icons{
	Step:     ">",
	Build:    ">",
	Diff:     ">",
	Activate: ">",
	Hook:     ">",
	Warn:     "!",
	Stop:     "■",
	Restart:  "↻",
	Reload:   "⟳",
	Start:    "▸",
	Running:  "⏵",
	Done:     "✔",
	Planned:  "⏸",
	Failed:   "✗",
	Download: "↓",
	Upload:   "↑",
	Clock:    "⏱",
	Summary:  "∑",
	Gap:      " ",
}

var Nerd = Icons{
	Running:  "",
	Done:     "",
	Planned:  "",
	Failed:   "",
	Download: "",
	Upload:   "",
	Clock:    "",
	Summary:  "\U000f04a0",
	Gap:      " ",
}

func DetectIcons(getenv func(string) string) *Icons {
	switch strings.ToLower(strings.TrimSpace(getenv("NERD_FONTS"))) {
	case "1", "true", "yes":
		return &Nerd
	case "0", "false", "no":
		return &Unicode
	}
	switch strings.ToLower(strings.TrimSpace(getenv("TERM_PROGRAM"))) {
	case "ghostty", "wezterm", "kitty":
		return &Nerd
	}
	switch strings.ToLower(getenv("TERM")) {
	case "xterm-ghostty", "xterm-kitty":
		return &Nerd
	}
	return &Unicode
}

func (i *Icons) With(icon, text string) string {
	return icon + i.Gap + text
}
