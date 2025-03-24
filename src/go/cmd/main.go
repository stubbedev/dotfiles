package main

import (
	"fmt"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type View int

const (
	SplashScreen View = iota
	Menu
)

type Model struct {
	view View
}

func (m Model) Init() tea.Cmd {
	// Show splash screen for 2 seconds, then switch to menu
	return tea.Batch(tea.Tick(time.Second*2, func(t time.Time) tea.Msg {
		return "showMenu"
	}))
}

func (m Model) View() string {
	switch m.view {
	case SplashScreen:
		return "Welcome to the Application!\nLoading...\n"
	case Menu:
		return "Main Menu:\n1. Install\n2. Browse Source\nPress 'q' to quit."
	default:
		return "Unknown view"
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case string:
		if msg == "showMenu" {
			m.view = Menu
		}
	case tea.KeyMsg:
		switch msg.String() {
		case "q":
			return m, tea.Quit
		case "1":
			if m.view == Menu {
				fmt.Println("Install selected")
			}
		case "2":
			if m.view == Menu {
				fmt.Println("Browse Source selected")
			}
		}
	}
	return m, nil
}

func main() {
	p := tea.NewProgram(Model{view: SplashScreen})

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error starting application: %v", err)
		os.Exit(1)
	}
}
