# JSON state-file mutators run at activation time.
#
# Both builders shell out to jq so mutations happen against the live
# file, preserving every byte the owning app wrote between evaluation
# and activation. See each function's comment for when to prefer one.
{
  pkgs ? null,
}:
let
  # Guard inside function bodies — callers may import lib.nix without
  # pkgs and only force these when they call the builder.
  requirePkgs = name: if pkgs == null then throw "homeLib.${name}: pkgs is required" else pkgs;
in
{
  # Recursively merge `patch` (a Nix attrset) onto whatever JSON is
  # currently at `target`, writing the result back atomically.
  #
  # Use this for state files the owning app rewrites at runtime
  # (claude-code's ~/.claude.json, ~/.claude/settings.json, …). Doing
  # the merge at *activation* time — instead of `recursiveUpdate`-ing
  # against `builtins.readFile` at eval time — preserves every byte
  # the app wrote between evaluation and activation. The eval-time
  # approach silently drops anything written in that window.
  #
  # name    — basename for the rendered patch derivation in /nix/store.
  # target  — absolute path to the live JSON file.
  # patch   — attrset to merge in (right-side wins on conflicts, same
  #           semantics as lib.recursiveUpdate / jq's `*`).
  # mode    — file mode used only when target doesn't yet exist
  #           (default 0600 — most app state files want this).
  #
  # cmp-before-mv: skip the rename when the merged result is already
  # byte-identical to the live file. Avoids racing against the app's
  # own writes once the patch is in place (steady-state behaviour).
  mergeJsonPatch =
    {
      name,
      target,
      patch,
      mode ? "0600",
    }:
    let
      p = requirePkgs "mergeJsonPatch";
      patchFile = p.writeText "${name}.json" (builtins.toJSON patch);
    in
    ''
      mkdir -p "$(dirname "${target}")"
      if [ -f "${target}" ]; then
        ${p.jq}/bin/jq -s '(.[0] // {}) * .[1]' "${target}" "${patchFile}" \
          > "${target}.hm-tmp"
        if cmp -s "${target}.hm-tmp" "${target}"; then
          rm -f "${target}.hm-tmp"
        else
          mv "${target}.hm-tmp" "${target}"
        fi
      else
        install -m ${mode} "${patchFile}" "${target}"
      fi
    '';

  # Authoritatively set a single top-level key in a JSON file, leaving every
  # other key untouched. Unlike mergeJsonPatch (deep `*` merge, additive-only),
  # this REPLACES the key's value wholesale, so entries removed from `value`
  # actually disappear from the target. Use for a managed subtree that lives
  # inside an otherwise stateful, externally-owned file (e.g. mcpServers in
  # ~/.claude.json) where merging would leave stale entries behind.
  setJsonKey =
    {
      name,
      target,
      key,
      value,
      mode ? "0600",
    }:
    let
      p = requirePkgs "setJsonKey";
      valueFile = p.writeText "${name}.json" (builtins.toJSON value);
    in
    ''
      mkdir -p "$(dirname "${target}")"
      if [ -f "${target}" ]; then
        ${p.jq}/bin/jq --slurpfile v "${valueFile}" '.["${key}"] = $v[0]' "${target}" \
          > "${target}.hm-tmp"
        if cmp -s "${target}.hm-tmp" "${target}"; then
          rm -f "${target}.hm-tmp"
        else
          mv "${target}.hm-tmp" "${target}"
        fi
      else
        ${p.jq}/bin/jq -n --slurpfile v "${valueFile}" '{ "${key}": $v[0] }' > "${target}"
        chmod ${mode} "${target}"
      fi
    '';
}
