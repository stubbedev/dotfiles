#!/usr/bin/env bash

toggle_window() {
	local window_name="$1"
	shift
	local current_window
	local current_path

	current_window=$(tmux display-message -p '#W')
	current_path=$(tmux display-message -p -F "#{pane_current_path}")

	if [ "$current_window" = "$window_name" ]; then
		tmux last-window
		return
	fi

	if tmux select-window -t "=$window_name" 2>/dev/null; then
		return
	fi

	if [ "$#" -eq 0 ]; then
		return
	fi

	tmux new-window -c "$current_path" -n "$window_name" "$@"
}

session_init() {
	local session_name
	local pane_id
	local target
	local current_path
	local has_git=0

	session_name=$(tmux display-message -p -F "#{hook_session_name}")
	if [ -z "$session_name" ]; then
		session_name=$(tmux display-message -p -F "#S")
	fi

	pane_id=$(tmux display-message -p -F "#{hook_pane}")
	if [ -z "$pane_id" ]; then
		pane_id=$(tmux display-message -p -F "#{pane_id}")
	fi

	current_path=$(tmux display-message -p -t "$pane_id" -F "#{pane_current_path}")
	if [ -n "$current_path" ] && git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
		has_git=1
	fi

	if [ -n "$session_name" ]; then
		target="$session_name"
	else
		target=$(tmux display-message -p -F "#S")
	fi

	tmux set-option -q -t "$target" @stubbe_has_git "$has_git"
}

refresh_session_git_flag() {
	local session_name
	local pane_id
	local current_path
	local has_git=0

	session_name=$(tmux display-message -p -F "#S")
	pane_id=$(tmux display-message -p -F "#{pane_id}")
	current_path=$(tmux display-message -p -t "$pane_id" -F "#{pane_current_path}")

	if [ -n "$current_path" ] && git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
		has_git=1
	fi

	tmux set-option -q -t "$session_name" @stubbe_has_git "$has_git"
}

toggle_lazygit_window() {
	refresh_session_git_flag

	if [ "$(tmux show-option -qv @stubbe_has_git)" != "1" ]; then
		return
	fi

	if ! command -v tmux-lazy-git >/dev/null 2>&1; then
		return
	fi

	toggle_window "lazygit" tmux-lazy-git
}

toggle_sysmon_window() {
	if ! command -v tmux-system-monitor >/dev/null 2>&1; then
		return
	fi

	toggle_window "sysmon" tmux-system-monitor
}

toggle_lazydocker_window() {
	if ! command -v tmux-lazy-docker >/dev/null 2>&1; then
		return
	fi

	toggle_window "lazydocker" tmux-lazy-docker
}

toggle_opencode_window() {
	if ! command -v tmux-opencode >/dev/null 2>&1; then
		return
	fi

	toggle_window "opencode" tmux-opencode
}

case "$1" in
"toggle_lazygit_window")
	toggle_lazygit_window
	;;
"toggle_sysmon_window")
	toggle_sysmon_window
	;;
"toggle_lazydocker_window")
	toggle_lazydocker_window
	;;
"toggle_opencode_window")
	toggle_opencode_window
	;;
"session_init")
	session_init
	;;
esac
