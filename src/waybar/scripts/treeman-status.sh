#!/usr/bin/env bash

# Waybar module: surface treeman worktree processing state.
#
# Pulls `treeman worktree list --json` and hands the whole shape to jq.
# jq does the grouping, escaping, and JSON emission in one pass — keeps
# the shell layer to environment checks and the subprocess call.

set -u

ICON_ACTIVE=$'\U000f04ad'  # nf-md-source_branch_sync
ICON_IDLE=$'\U000f062c'    # nf-md-source_branch

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
    --arg icon_idle "$ICON_IDLE" '
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

    map({
        repo:    repo_label,
        branch:  (.branch // "-"),
        state:   (.state // "unknown"),
        is_main: (.is_main // false),
        active:  ((.state // "") != "ready"),
    }) as $rows
    | ($rows | length)                          as $total
    | ($rows | map(select(.active)) | length)   as $active
    | ($rows | group_by(.repo) | map({
        repo:   .[0].repo,
        total:  length,
        items:  sort_by([(.is_main | not), .branch]),
        active: map(select(.active)),
      }))                                       as $by_repo
    | def fmt_item: "  • \(if .is_main then "★ " else "" end)\(.branch)\(if .active then " (\(.state))" else "" end)";
      if $active > 0 then {
        text: "\($icon_active) \($active)/\($total)",
        class: "active",
        tooltip: (
          ["Treeman: \($active) processing / \($total) total"]
          + (
              $by_repo
              | map(select(.active | length > 0))
              | sort_by(.repo)
              | map(
                  "\n\(.repo)  (\(.active | length)/\(.total) active)"
                  + (.active | map("\n" + fmt_item) | join(""))
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
