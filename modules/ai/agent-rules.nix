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
      '';
    in
    lib.mkMerge [
      (lib.mkIf config.features.claudeCode {
        home.file.".claude/CLAUDE.md".text = rules + "\n@~/.claude/local.md\n";
      })
      (lib.mkIf config.features.harness { xdg.configFile."AGENTS.md".text = rules; })
    ];
}
