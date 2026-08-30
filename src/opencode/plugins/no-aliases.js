// Agent shell calls must never inherit an alias that blocks on a prompt nobody
// can answer (rm='rm -i', cp='cp -i', mv='mv -i' in modules/shell.nix). Same
// guard as the claude PreToolUse hook (modules/ai/claude-code.nix): prepend
// `unalias -a` on its OWN line — zsh expands aliases while parsing a line, so
// a `;`-joined one comes too late. opencode's bash tool spawns a
// non-interactive shell today, so this usually has nothing to clear; it exists
// so a future interactive-shell default cannot hang the agent.
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