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

reload_animation() {
	local colors=("#cba6f7" "#89b4fa" "#a6e3a1" "#f9e2af" "#f38ba8")
	local chars=("" "" "✶" "✸" "❄" "󰼪" "❅" "❆" "✹" "✺" "󰼪")
	local original
	original=$(tmux show-option -gv status-right 2>/dev/null)

	for _ in 1 2 3; do
		for i in "${!chars[@]}"; do
			local color="${colors[$((i % ${#colors[@]}))]}"
			tmux set -g status-right "#[fg=${color},bold]${chars[$i]}"
			sleep 0.08
		done
	done

	tmux set -g status-right "$original"
}

move_pane_to_window() {
	local target_n="$1"
	local current_window pane_width pane_height max_window

	current_window=$(tmux display-message -p "#{window_index}")
	if [ "${current_window}" = "${target_n}" ]; then
		return
	fi

	if tmux list-windows -F "#{window_index}" | grep -q "^${target_n}$"; then
		pane_width=$(tmux display-message -p "#{pane_width}")
		pane_height=$(tmux display-message -p "#{pane_height}")
		if [ "$pane_width" -gt "$((pane_height * 2))" ]; then
			tmux join-pane -h -t ":${target_n}"
		else
			tmux join-pane -t ":${target_n}"
		fi
	else
		max_window=$(tmux list-windows -F "#{window_index}" | sort -n | tail -1)
		if [ "${target_n}" -gt "$((max_window + 1))" ]; then
			tmux break-pane -t ":$((max_window + 1))"
		else
			tmux break-pane -t ":${target_n}"
		fi
	fi
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
"reload_animation")
	reload_animation
	;;
"move_pane_to_window")
	move_pane_to_window "$2"
	;;
esac
