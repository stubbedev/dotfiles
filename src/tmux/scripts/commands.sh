#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

toggle_window() {
	local window_name="$1"
	shift
	local command=("$@")
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

	if [ "${#command[@]}" -eq 0 ]; then
		return
	fi

	tmux new-window -c "$current_path" -n "$window_name" "${command[@]}"
}

toggle_window_app() {
	local command="$1"

	if [ -z "$command" ]; then
		return
	fi

	if [[ -z "$TMUX" ]]; then
		$command
		return
	fi

	$command

	if [[ $? -ne 0 ]] || ! pgrep -f "$command" >/dev/null 2>&1; then
		tmux kill-pane 2>/dev/null || exit 0
	fi
}

select_lazygit_command() {
	if command -v lazygit >/dev/null 2>&1; then
		echo "lazygit"
	elif command -v bit >/dev/null 2>&1; then
		echo "bit"
	fi
}

select_sysmon_command() {
	if command -v btop >/dev/null 2>&1; then
		echo "btop"
	elif command -v htop >/dev/null 2>&1; then
		echo "htop"
	fi
}

select_lazydocker_command() {
	if command -v lazydocker >/dev/null 2>&1; then
		echo "lazydocker"
	fi
}

get_session_git_flag() {
	local session_name

	session_name=$(tmux display-message -p -F "#S")
	tmux show-option -qv -t "$session_name" @stubbe_has_git
}

session_init() {
	local session_name
	local hook_session_name
	local hook_pane_id
	local pane_id
	local current_path
	local has_git=0

	hook_session_name=$(tmux display-message -p -F "#{hook_session_name}")
	if [ -n "$hook_session_name" ]; then
		session_name="$hook_session_name"
	else
		session_name=$(tmux display-message -p -F "#S")
	fi

	hook_pane_id=$(tmux display-message -p -F "#{hook_pane}")
	if [ -n "$hook_pane_id" ]; then
		pane_id="$hook_pane_id"
	else
		pane_id=$(tmux display-message -p -F "#{pane_id}")
	fi

	current_path=$(tmux display-message -p -t "$pane_id" -F "#{pane_current_path}")

	if [ -n "$current_path" ]; then
		if [ -d "$current_path/.git" ] || git -C "$current_path" rev-parse --git-dir >/dev/null 2>&1; then
			has_git=1
		fi
	fi

	if [ -n "$session_name" ]; then
		tmux set-option -q -t "$session_name" @stubbe_has_git "$has_git"
	else
		tmux set-option -q @stubbe_has_git "$has_git"
	fi
}

run_tool() {
	local command="$1"

	if [ -z "$command" ]; then
		return
	fi

	toggle_window_app "$command"
}

toggle_lazygit_window() {
	local has_git
	local tool_command

	has_git=$(get_session_git_flag)
	if [ "$has_git" != "1" ]; then
		return
	fi

	tool_command=$(select_lazygit_command)
	if [ -z "$tool_command" ]; then
		return
	fi

	toggle_window "lazygit" "$CURRENT_DIR/commands.sh" run-tool "$tool_command"
}

toggle_sysmon_window() {
	local tool_command

	tool_command=$(select_sysmon_command)
	if [ -z "$tool_command" ]; then
		return
	fi

	toggle_window "sysmon" "$CURRENT_DIR/commands.sh" run-tool "$tool_command"
}

toggle_lazydocker_window() {
	local tool_command

	tool_command=$(select_lazydocker_command)
	if [ -z "$tool_command" ]; then
		return
	fi

	toggle_window "lazydocker" "$CURRENT_DIR/commands.sh" run-tool "$tool_command"
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
"run-tool")
	shift
	run_tool "$@"
	;;
"session_init")
	session_init
	;;
esac
