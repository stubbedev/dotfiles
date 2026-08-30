// Put LSP warnings back in front of the model.
//
// opencode's edit/write/patch tools append diagnostics to their own output via
// Diagnostic.report(), which is hardcoded to `severity === 1` -- errors only,
// capped at 20. Everything else the language server said is dropped, even
// though the renderer beside it already knows WARN/INFO/HINT.
//
// The full, unfiltered map survives on the tool result as
// `metadata.diagnostics` (path -> Diagnostic[]), and "tool.execute.after"
// receives that result object by reference, so appending here reaches the
// model the same way the built-in block does.
//
// Loaded by ~/.config/opencode/plugins/ (glob: `{plugin,plugins}/*.{ts,js}`,
// symlinks followed), wired in modules/ai/opencode.nix.

const LABEL = { 2: "WARN", 3: "INFO", 4: "HINT" }

// Same cap upstream uses for errors, applied per file.
const LIMIT = 20

const TOOLS = new Set(["edit", "write", "patch"])

function format(diagnostics) {
  const lines = []
  for (const d of diagnostics) {
    const label = LABEL[d?.severity]
    if (!label) continue // severity 1 is already in the built-in block
    const start = d.range?.start
    if (!start) continue
    lines.push(`${label} [${start.line + 1}:${start.character + 1}] ${d.message}`)
    if (lines.length === LIMIT) break
  }
  return lines
}

export const LspWarnings = async () => ({
  "tool.execute.after": async (input, output) => {
    if (!TOOLS.has(input.tool)) return
    // A throw here propagates into the tool call, so a malformed diagnostic
    // must never cost the edit itself.
    try {
      for (const [file, diagnostics] of Object.entries(output.metadata?.diagnostics ?? {})) {
        const lines = format(diagnostics ?? [])
        if (lines.length) {
          output.output += `\n<diagnostics file="${file}">\n${lines.join("\n")}\n</diagnostics>`
        }
      }
    } catch {
      // Diagnostics are an extra; the edit result stands on its own.
    }
  },
})

// Self-check: `node src/opencode/plugins/lsp-warnings.js`
if (import.meta.main) {
  const { strict: assert } = await import("node:assert")
  const at = (line, severity, message) => ({
    severity,
    message,
    range: { start: { line, character: 2 } },
  })

  assert.deepEqual(format([at(0, 1, "boom")]), [], "errors stay with the built-in block")
  assert.deepEqual(format([at(3, 2, "unused")]), ["WARN [4:3] unused"])
  assert.deepEqual(format([at(0, 3, "note"), at(1, 4, "hint")]), ["INFO [1:3] note", "HINT [2:3] hint"])
  assert.equal(format(Array.from({ length: 50 }, () => at(0, 2, "x"))).length, LIMIT)
  assert.deepEqual(format([{ severity: 2 }, at(0, 2, "ok")]), ["WARN [1:3] ok"], "missing range is skipped")
  console.log("ok")
}
