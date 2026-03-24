# Agent Guidelines

## Web Search

Use `websearch_cited` whenever uncertain about any fact, version,
API, or process. Do not guess — search instead. Verify the current
date is reflected in your answers.

Do NOT use the built-in `websearch` tool — use `websearch_cited` instead.

## Scope

Fix only what was asked. Do not refactor, rename, or restructure
adjacent code unless explicitly requested.

Before making changes that touch more than 3 files or alter structure,
state your plan and wait for confirmation.

## Verification

After making changes, run the relevant build, lint, or test command.
Do not stop at the edit — confirm it works.

## File Operations

Always edit existing files. Never create a new file when an existing
one can be modified. Never create markdown files to document changes
unless explicitly asked. If asked to document without a target path,
write to `README.md`.

## Output

Do not summarize what you just did. Do not restate the user's request.
Do not add filler like "Great!" or "Sure!". Respond only with what
is necessary — actions, results, or direct answers.

## Secrets & PII

`opencode-vibeguard` redacts secrets and PII before they reach the
LLM. Do not attempt to work around or reconstruct redacted
placeholders.
