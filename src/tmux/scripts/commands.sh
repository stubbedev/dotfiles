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

toggle_claude_window() {
  if ! command -v tmux-claude >/dev/null 2>&1; then
    return
  fi

  toggle_window "claude" tmux-claude
}

pane_is_pinned() {
  [ "$(tmux show-options -t "$1" -pqv @pinned)" = "1" ]
}

toggle_pin() {
  local pane_id
  pane_id=$(tmux display-message -p "#{pane_id}")
  if pane_is_pinned "$pane_id"; then
    tmux set -p -t "$pane_id" @pinned 0
  else
    tmux set -p -t "$pane_id" @pinned 1
  fi
}

kill_pane() {
  local pending pane_id window_id

  pane_id=$(tmux display-message -p "#{pane_id}")
  if ! pane_is_pinned "$pane_id"; then
    tmux kill-pane
    return
  fi

  pending=$(tmux display-message -p "#{@kill_pane_pending}")
  if [ "$pending" = "1" ]; then
    tmux kill-pane
    return
  fi

  window_id=$(tmux display-message -p "#{window_id}")
  tmux set -p -t "$pane_id" @kill_pane_pending 1
  pending_animation "$pane_id" "$window_id" pane
}

kill_window() {
  local pending pane_id window_id any_pinned pid

  window_id=$(tmux display-message -p "#{window_id}")

  any_pinned=0
  while IFS= read -r pid; do
    if pane_is_pinned "$pid"; then
      any_pinned=1
      break
    fi
  done < <(tmux list-panes -t "$window_id" -F "#{pane_id}")

  if [ "$any_pinned" != "1" ]; then
    tmux kill-window
    return
  fi

  pending=$(tmux display-message -p "#{@kill_window_pending}")
  if [ "$pending" = "1" ]; then
    tmux kill-window
    return
  fi

  pane_id=$(tmux display-message -p "#{pane_id}")
  tmux set -w -t "$window_id" @kill_window_pending 1
  pending_animation "$pane_id" "$window_id" window
}

kill_server_confirm() {
  local pending
  pending=$(tmux show-option -gv @kill_server_pending 2>/dev/null)
  if [ "$pending" = "1" ]; then
    tmux kill-server
    return
  fi

  tmux set -g @kill_server_pending 1
  sleep 1.5
  tmux set -g @kill_server_pending 0 2>/dev/null
}

toggle_mark_join() {
  local pane_marked pane_marked_set pane_width pane_height

  pane_marked=$(tmux display-message -p "#{pane_marked}")
  if [ "$pane_marked" = "1" ]; then
    tmux select-pane -M
    return
  fi

  pane_marked_set=$(tmux display-message -p "#{pane_marked_set}")
  if [ "$pane_marked_set" != "1" ]; then
    tmux select-pane -m
    return
  fi

  pane_width=$(tmux display-message -p "#{pane_width}")
  pane_height=$(tmux display-message -p "#{pane_height}")
  if [ "$pane_width" -gt "$((pane_height * 2))" ]; then
    tmux join-pane -h
  else
    tmux join-pane
  fi
}

pending_animation() {
  local pane_id="$1"
  local win_id="$2"
  local scope="$3" # "pane" or "window"
  local duration_us=300000
  local fill_style="#[bg=#f38ba8,fg=#1e1e2e,bold]"

  local flag_scope flag_target flag_name
  case "$scope" in
  pane)   flag_scope=-p ; flag_target="$pane_id" ; flag_name=@kill_pane_pending ;;
  window) flag_scope=-w ; flag_target="$win_id"  ; flag_name=@kill_window_pending ;;
  esac
  trap "tmux set -wu -t '$win_id' window-status-current-format 2>/dev/null; \
        tmux set $flag_scope -t '$flag_target' $flag_name 0 2>/dev/null" EXIT INT TERM

  shopt -s extglob
  local raw base_style template
  raw=$(tmux show-options -gqv window-status-current-format)
  [[ "$raw" =~ ^(#\[[^]]*\]) ]] && base_style="${BASH_REMATCH[1]}"
  template="${raw//#\[*([^]])\]/}"

  local rendered
  rendered=$(tmux display-message -p -t "$win_id" "$template")

  local -a chars=()
  while IFS= read -r c; do
    chars+=("$c")
  done < <(LC_ALL=C.UTF-8 grep -o . <<<"$rendered")

  local per_cell total=${#chars[@]}
  if (( total == 0 )); then
    printf -v per_cell "0.%06d" "$duration_us"
    sleep "$per_cell"
    return
  fi
  printf -v per_cell "0.%06d" "$((duration_us / total))"

  local i j frame style
  for ((i = 1; i <= total; i++)); do
    frame=""
    for ((j = 0; j < total; j++)); do
      ((j < i)) && style="$fill_style" || style="$base_style"
      frame+="${style}${chars[$j]}"
    done
    tmux set -wt "$win_id" window-status-current-format "$frame" 2>/dev/null
    sleep "$per_cell"
  done
}

reload_animation() {
  local chars=("⡿" "⣟" "⣯" "⣷" "⣾" "⣽" "⣻" "⢿")
  local original
  original=$(tmux show-option -gv status-left 2>/dev/null)
  trap "tmux set -g status-left '$original' 2>/dev/null" EXIT INT TERM

  local n=${#chars[@]}
  local total=$((n * 2))
  local peak=$((n - 1))
  local i t r g b color
  for ((i = 0; i < total; i++)); do
    (( i < n )) && t=$i || t=$((total - 1 - i))
    r=$((243 + 6 * t / peak))
    g=$((139 + 87 * t / peak))
    b=$((168 + 7 * t / peak))
    printf -v color "#%02x%02x%02x" "$r" "$g" "$b"
    tmux set -g status-left "#[bg=default,bold,fg=${color}] ${chars[i % n]} "
    sleep 0.08
  done
}

move_pane() {
  local direction="$1"
  local pane_id pane_count edge_flag target_token target_pane
  local pane_width pane_height window_width window_height
  local join_flags=()
  pane_id=$(tmux display-message -p "#{pane_id}")
  pane_count=$(tmux display-message -p "#{window_panes}")
  pane_width=$(tmux display-message -p "#{pane_width}")
  pane_height=$(tmux display-message -p "#{pane_height}")
  window_width=$(tmux display-message -p "#{window_width}")
  window_height=$(tmux display-message -p "#{window_height}")

  if [ "$pane_count" -le 1 ]; then
    return
  fi

  case "$direction" in
  L)
    edge_flag=$(tmux display-message -p "#{pane_at_left}")
    if [ "$edge_flag" = "0" ]; then
      tmux swap-pane -t "{left-of}"
    elif [ "$pane_height" -eq "$window_height" ]; then
      return
    else
      target_token="{left}"
      join_flags=(-b -h)
    fi
    ;;
  R)
    edge_flag=$(tmux display-message -p "#{pane_at_right}")
    if [ "$edge_flag" = "0" ]; then
      tmux swap-pane -t "{right-of}"
    elif [ "$pane_height" -eq "$window_height" ]; then
      return
    else
      target_token="{right}"
      join_flags=(-h)
    fi
    ;;
  U)
    edge_flag=$(tmux display-message -p "#{pane_at_top}")
    if [ "$edge_flag" = "0" ]; then
      tmux swap-pane -t "{up-of}"
    elif [ "$pane_width" -eq "$window_width" ]; then
      return
    else
      target_token="{top}"
      join_flags=(-b)
    fi
    ;;
  D)
    edge_flag=$(tmux display-message -p "#{pane_at_bottom}")
    if [ "$edge_flag" = "0" ]; then
      tmux swap-pane -t "{down-of}"
    elif [ "$pane_width" -eq "$window_width" ]; then
      return
    else
      target_token="{bottom}"
    fi
    ;;
  esac

  if [ -n "$target_token" ]; then
    target_pane=$(tmux display-message -p -t "$target_token" "#{pane_id}")
    if [ "$target_pane" = "$pane_id" ]; then
      while IFS= read -r target_pane; do
        if [ "$target_pane" != "$pane_id" ]; then
          break
        fi
      done <<EOF
$(tmux list-panes -F "#{pane_id}")
EOF
    fi
    if [ -z "$target_pane" ] || [ "$target_pane" = "$pane_id" ]; then
      return
    fi
    tmux move-pane -d "${join_flags[@]}" -s "$pane_id" -t "$target_pane"
  fi

  tmux select-pane -t "$pane_id"
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
    if [ "${target_n}" -gt "${max_window}" ]; then
      tmux break-pane
    else
      tmux break-pane -t ":${target_n}"
    fi
  fi
}

case "$1" in
"toggle_pin")               toggle_pin ;;
"kill_pane")                kill_pane ;;
"kill_window")              kill_window ;;
"kill_server_confirm")      kill_server_confirm ;;
"toggle_mark_join")         toggle_mark_join ;;
"toggle_lazygit_window")    toggle_lazygit_window ;;
"toggle_sysmon_window")     toggle_sysmon_window ;;
"toggle_lazydocker_window") toggle_lazydocker_window ;;
"toggle_claude_window")     toggle_claude_window ;;
"move_pane")                move_pane "$2" ;;
"move_pane_to_window")      move_pane_to_window "$2" ;;
"session_init")             session_init ;;
"reload_animation")         reload_animation ;;
"pending_animation")        pending_animation "$2" "$3" "$4" ;;
esac
