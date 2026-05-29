#!/usr/bin/env bash

# Waybar module: surface treeman worktree processing state.
#
# Pulls `treeman worktree list --json` and hands the whole shape to jq.
# jq does the grouping, escaping, and JSON emission in one pass — keeps
# the shell layer to environment checks and the subprocess call.

set -u

ICON_ACTIVE=$'\U000f04ad'  # nf-md-source_branch_sync
ICON_IDLE=$'\U000f062c'    # nf-md-source_branch
ICON_FAILED=$'\U000f0159'  # nf-md-close_network

empty='{"text":"","tooltip":"","class":""}'

if ! command -v treeman >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "$empty"
    exit 0
fi

raw=$(treeman worktree list --json 2>/dev/null) || raw=""
case "$raw" in
    ""|"null"|"[]") echo "$empty"; exit 0 ;;
esac

printf '%s' "$raw" | jq -c \
    --arg icon_active "$ICON_ACTIVE" \
    --arg icon_idle "$ICON_IDLE" \
    --arg icon_failed "$ICON_FAILED" '
    # Repo root: main worktree path itself, or path before /.worktrees/,
    # or parent dir for ad-hoc layouts. All string-split, no regex.
    def repo_root:
        if .is_main // false then .path // ""
        elif ((.path // "") | contains("/.worktrees/"))
            then (.path | split("/.worktrees/") | .[0])
        else ((.path // "") | split("/") | .[:-1] | join("/"))
        end;
    def repo_label:
        (repo_root | split("/") | .[-1]) as $base
        | if ($base // "") == "" then "?" else $base end;

    # Classify each row: failed > active > idle.
    map(. as $w | {
        repo:       repo_label,
        branch:     ($w.branch // "-"),
        state:      ($w.state // "unknown"),
        is_main:    ($w.is_main // false),
        failed:     (($w.state // "") | IN("error", "failed")),
        processing: (($w.state // "") | IN("preparing", "setup", "teardown")),
        nonready:   (($w.state // "") != "ready"),
    }) as $rows
    | ($rows | length)                            as $total
    | ($rows | map(select(.failed))     | length) as $n_failed
    | ($rows | map(select(.processing)) | length) as $n_proc
    | ($rows | group_by(.repo) | map({
        repo:     .[0].repo,
        total:    length,
        items:    sort_by([(.is_main | not), .branch]),
        nonready: map(select(.nonready)),
      }))                                         as $by_repo
    | def fmt_item:
        "  • \(if .is_main then "★ " else "" end)\(.branch)"
        + (if .nonready then " (\(.state))" else "" end);
      if $n_failed > 0 then {
        text: "\($icon_failed) \($n_failed)\(if $n_proc > 0 then "+\($n_proc)" else "" end)/\($total)",
        class: "failed",
        tooltip: (
          ["Treeman: \($n_failed) failed\(if $n_proc > 0 then ", \($n_proc) processing" else "" end) / \($total) total"]
          + (
              $by_repo
              | map(select(.nonready | length > 0))
              | sort_by(.repo)
              | map(
                  "\n\(.repo)  (\(.nonready | length)/\(.total) need attention)"
                  + (.nonready | map("\n" + fmt_item) | join(""))
                )
            )
          | join("\n")
        ),
      } elif $n_proc > 0 then {
        text: "\($icon_active) \($n_proc)/\($total)",
        class: "active",
        tooltip: (
          ["Treeman: \($n_proc) processing / \($total) total"]
          + (
              $by_repo
              | map(select(.nonready | length > 0))
              | sort_by(.repo)
              | map(
                  "\n\(.repo)  (\(.nonready | length)/\(.total) active)"
                  + (.nonready | map("\n" + fmt_item) | join(""))
                )
            )
          | join("\n")
        ),
      } else {
        text: "\($icon_idle) \($total)",
        class: "",
        tooltip: (
          $by_repo
          | sort_by(.repo)
          | map(
              "\(.repo)  (\(.total))"
              + (.items | map("\n" + fmt_item) | join(""))
            )
          | join("\n\n")
        ),
      } end
'
