_: {
  flake.modules.homeManager.agentRules =
    { config, lib, ... }:
    let
      rules = ''
        # Global coding principles

        These apply to every repo. A repo's own CLAUDE.md/AGENTS.md wins where it is more specific.

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
        - **Right complexity.** Pick the data structure that makes the operation cheap (hash lookup over linear scan). No N+1 queries or calls; batch them.
        - **Do work once.** Hoist invariant work out of loops, cache what is expensive and stable, do not recompute derived values.
        - Do not trade correctness or clarity for micro-optimisations in cold code.

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
      (lib.mkIf config.features.claudeCode { home.file.".claude/CLAUDE.md".text = rules; })
      (lib.mkIf config.features.harness { xdg.configFile."AGENTS.md".text = rules; })
    ];
}
