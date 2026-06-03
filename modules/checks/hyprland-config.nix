{ inputs, ... }:
{
  # `nix flake check` validates src/hypr/hyprland.lua with Hyprland's own
  # --verify-config (headless config parse). Catches the whole class of bugs
  # that only surface at login: unknown/renamed config keys, wrong value
  # types, hy3 plugin config errors, and lua errors — none of which a plain
  # lua syntax check sees.
  perSystem =
    { system, pkgs, ... }:
    let
      hyprland = inputs.hyprland.packages.${system}.hyprland;
      hy3 = inputs.hy3.packages.${system}.hy3;

      # Stand-in for the HM-generated nix.lua: loads the real hy3 plugin (so the
      # hy3 config block is actually validated) and returns colors/paths shaped
      # like the real thing. Any colors.<key> resolves to a valid color, so the
      # check never needs to track which palette entries hyprland.lua uses.
      testNixLua = pkgs.writeText "nix.lua" ''
        hl.plugin.load("${hy3}/lib/libhy3.so")
        return {
          paths = { scripts = "/tmp", shared = "/tmp" },
          colors = setmetatable({}, { __index = function() return "rgb(cba6f7)" end }),
        }
      '';
    in
    {
      checks.hyprland-config = pkgs.runCommand "check-hyprland-config" { } ''
        export HOME="$(mktemp -d)"
        export XDG_RUNTIME_DIR="$(mktemp -d)"
        mkdir -p "$HOME/.config/hypr"
        cp ${../../src/hypr/hyprland.lua} "$HOME/.config/hypr/hyprland.lua"
        cp ${testNixLua} "$HOME/.config/hypr/nix.lua"

        if ${hyprland}/bin/Hyprland --verify-config 2>&1 | tee log.txt | grep -q "config ok"; then
          touch "$out"
        else
          echo "hyprland.lua failed Hyprland --verify-config:" >&2
          cat log.txt >&2
          exit 1
        fi
      '';
    };
}
