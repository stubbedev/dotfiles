// Same unalias guard as the claude PreToolUse hook. `unalias -a` must be on its
// own line: zsh expands aliases while parsing a line.
//
// Loaded by ~/.config/opencode/plugins/ (glob: `{plugin,plugins}/*.{ts,js}`,
// symlinks followed), wired in modules/ai/opencode.nix.

const UNALIAS = "unalias -a 2>/dev/null\n"

export const NoAliases = async () => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return
    output.args.command = UNALIAS + output.args.command
  },
})

// Self-check: `node src/opencode/plugins/no-aliases.js`
if (import.meta.main) {
  const { strict: assert } = await import("node:assert")
  const hooks = await NoAliases()
  const before = hooks["tool.execute.before"]

  const command = async (tool, cmd) => {
    const output = { args: { command: cmd } }
    await before({ tool, callID: "x" }, output)
    return output.args.command
  }

  assert.equal(await command("bash", "rm foo"), `${UNALIAS}rm foo`)
  assert.equal(await command("edit", "rm foo"), "rm foo", "non-bash tools are untouched")
  console.log("ok")
}