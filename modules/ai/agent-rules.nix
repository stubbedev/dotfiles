_: {
  flake.modules.homeManager.agentRules =
    { config, lib, ... }:
    let
      rules = ''
        # Global coding principles

        These apply to every repo. A repo's own CLAUDE.md/AGENTS.md wins where it is more specific.

        ## Communication

        - Always write in English, even when the ticket, PR, or user input is in another language. This applies to PR descriptions, commit messages, and documentation.

        ## Before writing

        - **Read before writing.** Find every caller and the existing tests first. When a signature or behaviour changes, update every call site in the same change.
        - **Verify APIs, never guess.** Confirm a function, flag or option exists in the version actually pinned (lockfile, source, docs) before writing against it.
        - **Ask or assume, explicitly.** If a requirement is ambiguous and the choice is costly to reverse, ask. Otherwise pick one and state the assumption.

        ## Design

        - **DRY, aggressively.** Every fact, constant, rule and piece of logic exists exactly once. On the second occurrence, extract it. Before writing anything, search for an existing helper, type or module that already does it and reuse or extend that. Derive values from their single source instead of restating them.
        - **Correct by construction.** Make invalid states unrepresentable: precise types, enums/sum types over strings and booleans, newtypes for distinct IDs/units, non-optional where a value must exist. Parse at the boundary into a validated type, then trust it; do not re-validate deep inside. Prefer APIs that cannot be misused over documenting how not to misuse them.
        - **The right solution, not the smallest diff.** Never pick a worse design to keep a change small. If doing it properly means refactoring callers, renaming, moving code or changing a signature, do it. Leave the code better structured than you found it within the scope of the task.
        - **Fix root causes.** No workarounds, special cases or retries layered over a bug you have not understood. Find why, fix it there.
        - **No silent fallbacks.** Fail loudly and early with a precise error. No swallowed exceptions, no default values that mask missing data, no `|| true` to make a failure go away.
        - **Delete freely.** Remove dead code, unused parameters, stale config, compatibility shims and leftover indirection instead of keeping them around. No backwards-compat layers unless explicitly asked.
        - **No speculative generality.** DRY means unifying what already repeats, not adding knobs, plugin points or abstraction layers for hypothetical futures.
        - **Pure core, effects at the edges.** Keep logic in pure functions over immutable data; push I/O, time, randomness and global state to the outermost layer.
        - **Single responsibility, small surface.** Minimal public API, narrowest visibility, no globals. Name things for what they are, consistently with the codebase.
        - **Minimal dependencies.** Prefer the standard library and dependencies already in the project. Never add a package for something trivial.
        - **Flat control flow.** Guard clauses and early returns over nested conditionals; composition over inheritance.

        ## Robustness

        - **Errors carry context.** Every error says what was being attempted and with which input. Wrap the underlying error, never replace it.
        - **Release what you acquire.** Close or free every file, lock, connection and process deterministically (`defer`, RAII, `with`). Timeouts on all network calls; no unbounded retries or queues.
        - **Atomic and idempotent.** Write to a temp file and rename into place, never half-write a target. Running an operation twice is safe; a partial failure leaves a consistent state.
        - **Untrusted input stays data.** Pass argv arrays, never interpolate into a shell string. Parameterised queries only. Secrets never in code, logs or error messages.
        - **Deterministic.** Never depend on map/hash iteration order, locale or the local time zone. Store and compute time in UTC. Output is stable across runs.
        - **Numeric and text correctness.** Watch overflow and off-by-one; never use floats for money; distinguish bytes, code points and graphemes.

        ## Performance

        When it is relevant (hot paths, loops, I/O, startup, anything run often):

        - **Fewest syscalls.** Batch reads/writes, buffer I/O, read a file once, avoid stat-then-open races and redundant existence checks (just open and handle the error). Prefer one process over a pipeline of subprocesses; prefer shell builtins over forking external tools.
        - **Fewest allocations.** Preallocate with known capacity, reuse buffers, borrow/slice instead of copying, avoid intermediate collections and string building in loops, stream instead of loading everything into memory.
        - **Right complexity.** Pick the data structure that makes the operation cheap (hash lookup over linear scan). Batch remote calls instead of one per item.
        - **Do work once.** Hoist invariant work out of loops, cache what is expensive and stable, do not recompute derived values.
        - Do not trade correctness or clarity for micro-optimisations in cold code.

        ## Data access

        Always, not only on known hot paths: every query to a database, search index, cache or other data store is written for production volume, never for the size of the test fixture. A query that works today and scans tomorrow is a bug.

        - **Every query is served by an index.** Before writing or changing a query, name the index that serves its filter, join, sort and grouping columns, respecting leftmost-prefix order. If none exists, add it in the same change as a migration. A full scan is acceptable only on a table that is provably small and bounded, and you say so.
        - **Prove it with the plan.** Run the store's plan tool (`EXPLAIN (ANALYZE, BUFFERS)`, `EXPLAIN QUERY PLAN`, `EXPLAIN FORMAT=JSON`, `.explain("executionStats")`) on every new or changed query against realistically sized data, and report the plan. Sequential/collection scans, filesorts, temp tables, hash joins over unbounded inputs or rows-examined far above rows-returned on a growing table mean the query is not done.
        - **Sargable predicates only.** No functions, casts, arithmetic or implicit type/collation conversions on indexed columns in `WHERE`, `JOIN` or `ORDER BY` (`date(created_at) = ?` becomes a half-open range). No leading-wildcard `LIKE`; use a trigram or full-text index. No `OR` across different columns that defeats the index; use `UNION ALL` or a matching index. Bind parameters with the column's exact type.
        - **Design indexes for the queries.** Composite order is equality columns, then range, then sort. Make hot reads index-only with covering columns (`INCLUDE`). Use partial or expression indexes for skewed or computed predicates. Index the referencing side of every foreign key. Every index is justified by a query it serves; drop redundant and unused ones, since each one taxes writes.
        - **No N+1.** Never query inside a loop. Fetch related rows with a join or one batched `IN`/`= ANY($1)` query, and eager-load ORM relations explicitly instead of relying on lazy loading.
        - **Read only what is used.** No `SELECT *`; project the needed columns so covering indexes apply. Every list query has a `LIMIT` and a deterministic `ORDER BY` served by an index, with a unique tiebreaker.
        - **Keyset pagination.** Paginate growing data by seeking on the indexed sort key (`WHERE (created_at, id) < ($1, $2)`), never with `OFFSET`.
        - **Cheap existence and counts.** Use `EXISTS` instead of `COUNT(*)` to test presence; no exact counts over large tables on request paths.
        - **Bulk writes, short transactions.** Multi-row `INSERT`, `COPY` or upsert, one transaction per batch, never row-at-a-time loops. Keep transactions and row locks as short and narrow as possible; no network calls while holding them.
        - **ORMs and query builders are not exempt.** Inspect the SQL they actually emit and hold it to every rule here.
        - **Non-relational stores too.** Design keys and secondary indexes from the access patterns. No `KEYS`, DynamoDB `Scan`, unindexed Mongo queries or unbounded range reads on request paths.
        - **Schema changes are online.** Build indexes without blocking writes (`CREATE INDEX CONCURRENTLY`, online DDL), avoid table-rewriting `ALTER`s on large tables, and backfill in bounded batches.
        - **Lock the plan in.** For hot-path queries, add a test that asserts the plan uses the intended index, so a regression to a scan fails CI.

        ## Style

        - **No comments.** Code must stand on its own through naming and structure. Only functional directives (lint disables, pragmas) are allowed. Rationale goes in the commit message or the response, never in the source.
        - Match the surrounding code's idiom, formatting and conventions. Where code you touch contradicts the principles above, fix it.
        - Run the project's formatter, linter and type checker, and keep them clean.
        - **Shell scripts.** `set -euo pipefail`, quote every expansion, shellcheck clean.
        - **No debugging leftovers.** Remove stray prints, commented-out code and temporary files before finishing.

        ## Verification

        - Build, test and exercise the change before calling it done. Say plainly what was verified and what was not.
        - Tests assert behaviour, not implementation. Add a test for every bug fixed.
        - **Never cheat a check.** Do not weaken, skip or delete a test, special-case test inputs, or update expected output to match broken behaviour. A failing check means the code is wrong until proven otherwise.
        - **No placeholders.** No TODOs, stubs, "simplified versions", mock data in production paths or unimplemented branches. Finish the whole thing, or state plainly what is missing.

        ## Scope and commits

        - Refactor whatever the task needs. Report unrelated problems you notice instead of silently fixing them.
        - One logical change per commit. The message explains why, since the source carries no comments.
        - **No attribution.** Never add commit trailers, PR lines, footers or annotations crediting yourself, this tool, or a session: no `Co-Authored-By`, no `Claude-Session`, no session URLs, no generated-with lines. Commit messages and PR descriptions carry the change and its rationale only.
      '';

      # Both engines read ~/.claude/skills: Claude Code at that path directly,
      # Harness because its global skill dirs are $XDG_CONFIG_HOME/harness,
      # $XDG_CONFIG_HOME/agents, ~/.agents and ~/.claude. One file, no copy to
      # keep in sync.
      issuesSkill = ''
        ---
        name: issues
        description: Review and burn down the open GitHub issues of the current repository in one batch. Lists the issues, reviews each one, groups them logically, then asks the user whether to work on everything, one group or a specific subset, and fixes the chosen groups with parallel sub-agents whose work never overlaps. Each issue is closed as its fix is committed, partially solved ones get a comment saying what landed and what did not, and anything discovered along the way is filed as a new issue. Use this whenever the user mentions GitHub issues in any working sense — "what issues do we have", "triage", "burn down the backlog", "fix these issues", "work through the issues" — or invokes /issues, even when they name no specific issue.
        ---

        # Issues

        Work the open issues of the current repository as one batch and leave
        GitHub reflecting the result: closed issues with a commit behind them,
        partial ones with a comment that says what landed and what did not, and
        new issues for everything found on the way.

        Arguments given to the skill (`$ARGUMENTS`) narrow or skip the opening
        questions: an `owner/repo` picks the repository, issue numbers skip the
        whole-issue listing for those issues only, and "review" means stop after
        the grouping.

        ## Ground rules

        - **Review before touching.** Every issue is read in full, body and
          comments, before it is grouped. An issue that is already fixed, a
          duplicate, or waiting on the reporter is not work; say so and leave it
          open rather than closing it on a guess.
        - **Overlap is about files, not issues.** Every file the selected work
          will touch belongs to exactly one agent at a time. Issues that share a
          file are the same group. An agent that discovers mid-work it needs a
          file another running agent owns stops and reports instead of editing
          it; the coordinator then either hands that file over once the other
          agent is done, or defers the issue with a comment.
        - **Trust the LSP, not the build.** Correctness comes from the language
          server: use LSP rename/references instead of text search for anything
          that spans call sites, and read the diagnostics that arrive after each
          edit. No compiles, no test runs, no formatter loops while work is in
          flight; they are slow, they fight each other across parallel agents,
          and they tell you nothing the diagnostics have not already said.
        - **One verification pass, at the end.** When every selected issue is
          committed, run the project's gates once, fix what they surface,
          commit the fixes, and only then push. A second pass means the first
          one was cut short, not that it was thorough.
        - **The coordinator owns git and gh.** Only the top-level agent commits,
          closes issues and pushes. Sub-agents edit files and report; a shared
          index is the one thing parallel agents cannot share safely.

        ## 1. Scope the repository

        ```sh
        gh auth status
        gh repo view --json nameWithOwner,defaultBranchRef --jq '.nameWithOwner'
        gh issue list --state open --limit 200 \
          --json number,title,labels,assignees,milestone,createdAt,updatedAt,comments,body
        ```

        If the working directory is not a repository, or the repository has more
        than one plausible upstream, ask which one before going further. Note
        the current branch and whether the working tree is dirty: a dirty tree
        gets a question before any agent starts, because the run commits.

        ## 2. Review each issue

        For every open issue, `gh issue view <n> --comments`, then open the code
        it refers to. Record:

        - **verdict** — actionable, needs-info, stale, duplicate, already-fixed.
          Only actionable ones become work; the rest are reported with one line
          of reasoning (and a comment on the issue when the reason is useful to
          the reporter).
        - **kind** — bug, feature, chore, question.
        - **area** — the files or module the fix lives in, from what you just
          read, not from the issue title.
        - **coupling** — other issues it depends on, blocks, or duplicates.
        - **size** — small enough for one agent, or big enough to split.

        Read the tests around the affected code while reviewing: the fix has to
        land with a test, and knowing the existing pattern changes the plan.

        ## 3. Group

        Group by the code the work touches and by dependency order, never by
        label or theme. Two issues that edit the same file are one group even if
        they look unrelated, because the alternative is two agents racing on one
        file. Issues where one must land before another are separate groups in a
        stated order, not one big group.

        Aim for groups small enough that an agent can finish one without
        touching a file it does not own. A group of five issues across five
        unrelated subsystems is five groups.

        ## 4. Offer the choice

        Present the groups as a short table — group, issue numbers and titles,
        area, order, one-line why they belong together — then ask with the
        question tool (`AskUserQuestion` in Claude Code) which to work on:

        - every group,
        - one named group,
        - a specific subset (then ask which numbers),
        - none, review only.

        Wait for the answer. Do not start work in the same breath as the
        question, and do not pick a default when the answer is unclear; a second
        question is cheaper than a batch of unwanted commits.

        ## 5. Dispatch

        Partition the selected groups into agents of disjoint file sets, at most
        five running at once. Give each agent, in the prompt:

        - the issue numbers, titles and full bodies it owns, plus the relevant
          comments,
        - the files it owns, and the explicit instruction not to edit any file
          outside them,
        - the repo conventions that apply (AGENTS.md, CLAUDE.md, neighbouring
          code, test patterns next to the touched code),
        - the rule that verification is the coordinator's job at the end: make
          the change, let the LSP diagnostics carry it, add the test, and report,
        - the instruction to return: files changed, what the diagnostics said,
          what is provably fixed, what part of which issue is not fixed, and any
          new problem found,
        - the instruction not to run git, not to commit, not to touch gh.

        Each issue's fix lands as its own logical change; an agent that cannot
        separate two issues into two changes reports that rather than bundling
        them.

        ## 6. Commit and close, issue by issue

        After an agent reports, review the diff, then commit per issue with the
        rationale in the message and a `Closes #<n>` or `Refs #<n>` trailer in
        the body.

        - Fully solved, in one command:

          ```sh
          gh issue close <n> --reason completed \
            --comment "Fixed in <short sha>: <one line on what changed>."
          ```

        - Partially solved, a comment and no close:

          ```sh
          gh issue comment <n> --body "<what landed in <short sha>, what is still missing, and why it did not land here>"
          ```

          Name the missing part concretely, not as "the rest".

        Both happen as the commit is made, not at the end of the run: the issue
        tracker should never show a solved issue as open because a later step
        failed.

        ## 7. Verify once, then push

        With every selected issue committed, run the gates the project declares
        — formatter, linter, typecheck, and the tests for the packages touched.
        Never the full suite when targets exist; scope it to what changed. Fix
        what the gates surface in follow-up commits, and keep the issue states
        honest if a fix turns out not to hold. Then push once, at the end, and
        report the branch.

        ## 8. File what you found

        Every bug, gap or contradiction noticed during the run becomes a new
        issue, with the context that makes it actionable: what was being done,
        what was observed, where, and why it matters. File it immediately so it
        is not lost to a later summarisation; do not let it widen the current
        batch.

        Solve a new issue in the same batch only when it blocks the selected
        work — say so in the issue, and reference it from the commit that fixes
        it. Everything else waits for a later run.

        ## 9. Report

        Finish with four lists, no prose padding:

        - closed — number, title, commit
        - partially solved — number, what landed, what remains
        - filed — number, one line
        - verification — the gates run and their result, and the push

        Anything left open because it was not selected, or because the run ran
        out of clean ways to divide it, goes in the report too.
      '';
      agentSkillEnabled = config.features.claudeCode || config.features.harness;
    in
    lib.mkMerge [
      (lib.mkIf config.features.claudeCode {
        home.file.".claude/CLAUDE.md".text = rules + "\n@~/.claude/local.md\n";
      })
      (lib.mkIf config.features.harness { xdg.configFile."AGENTS.md".text = rules; })
      (lib.mkIf agentSkillEnabled {
        home.file.".claude/skills/issues/SKILL.md".text = issuesSkill;
      })
    ];
}
