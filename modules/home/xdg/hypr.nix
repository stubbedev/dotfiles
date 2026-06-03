_: {
  flake.modules.homeManager.xdgHypr =
    {
      config,
      constants,
      lib,
      pkgs,
      systemInfo,
      homeLib,
      hy3,
      hyprland,
      ...
    }:
    let
      # LuaCATS type stubs for the `hl` API, generated from the exact pinned
      # Hyprland source so they stay in sync with the running version. Gives
      # lua-language-server completion/signatures when editing hyprland.lua.
      hlMetaStub = pkgs.runCommand "hl.meta.lua" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${hyprland}/meta/generateLuaStubs.py --root ${hyprland} --output "$out"
      '';
    in
    lib.mkIf config.features.hyprland {
      xdg.configFile =
        homeLib.xdgSources [
          # Hyprland 0.55+ Lua config. Compositor config lives in hyprland.lua;
          # it require()s the Nix-generated nix.lua below for dynamic values.
          "hypr/hyprland.lua"
          # Ecosystem daemons still use hyprlang (no Lua support).
          "hypr/hypridle.conf"
          "hypr/hyprlock.conf"
          "hypr/hyprpaper.conf"
          "hypr/hyprsunset.conf"
          "hypr/hyprtoolkit.conf"
          # Catppuccin color vars (hyprlang $vars). The compositor uses Lua
          # locals now, but hyprlock.conf + hyprlock.launch.sh still source
          # this hyprlang file, so it must stay deployed.
          "hypr/theme.conf"
          "hypr/scripts"
        ]
        // {
          # Dynamic, Nix-derived bits required() by hyprland.lua: cursor/NVIDIA
          # env and the hy3 plugin path (a /nix/store path only Nix knows).
          "hypr/nix.lua" = {
            text =
              let
                # hy3 is already built against the correct hyprland from the flake
                hy3-plugin = hy3.packages.${pkgs.stdenv.hostPlatform.system}.hy3;
              in
              ''
              -- Nix Generated
              -- Cursor — single source of truth: constants.theme.cursor/cursorSize.
              -- Mirrored by HM home.sessionVariables and (on NixOS) by
              -- environment.sessionVariables, but those don't propagate into
              -- Hyprland's process tree under non-NixOS session managers (SDDM
              -- on Ubuntu doesn't source hm-session-vars.sh), so we set them
              -- via Hyprland's own hl.env here too.
              hl.env("XCURSOR_THEME", "${constants.theme.cursor}")
              hl.env("XCURSOR_SIZE", "${toString constants.theme.cursorSize}")
              ${lib.optionalString systemInfo.hasNvidia ''
              -- Additional ENV VARS
              hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
              hl.env("LIBVA_DRIVER_NAME", "nvidia")
              hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
              hl.env("NVD_BACKEND", "direct")
              ''}
              -- Plugins
              hl.plugin.load("${hy3-plugin}/lib/libhy3.so")
              '';
          };

          # Generated hl API type stubs (lua_ls). src/hypr/.luarc.json points
          # the language server here.
          "hypr/hl.meta.lua".source = hlMetaStub;

          # hy3 ships no stubs; hand-written from hy3 hl0.55.0 dispatchers.cpp.
          # Extends HL.PluginNamespace (from hl.meta.lua) with the hy3 factories.
          "hypr/hy3.meta.lua".text = ''
            ---@meta

            ---@class HL.PluginNamespace
            ---@field hy3 HY3.API

            ---@class HY3.API
            ---@field make_group fun(kind: "h"|"v"|"tab"|"opposite", opts?: { toggle?: boolean, ephemeral?: boolean|"force" }): HL.Dispatcher
            ---@field change_group fun(kind: "h"|"v"|"tab"|"untab"|"toggletab"|"opposite"): HL.Dispatcher
            ---@field set_ephemeral fun(value: boolean|"true"|"false"): HL.Dispatcher
            ---@field move_focus fun(dir: "l"|"r"|"u"|"d"|"left"|"right"|"up"|"down", opts?: { visible?: boolean, warp?: boolean }): HL.Dispatcher
            ---@field toggle_focus_layer fun(opts?: { warp?: boolean }): HL.Dispatcher
            ---@field warp_cursor fun(): HL.Dispatcher
            ---@field move_window fun(dir: "l"|"r"|"u"|"d"|"left"|"right"|"up"|"down", opts?: { once?: boolean, visible?: boolean }): HL.Dispatcher
            ---@field move_to_workspace fun(workspace: string, opts?: { follow?: boolean, warp?: boolean }): HL.Dispatcher
            ---@field change_focus fun(arg: "top"|"bottom"|"raise"|"lower"|"tab"|"tabnode"): HL.Dispatcher
            ---@field focus_tab fun(opts: { direction?: "l"|"r"|"left"|"right", index?: integer, mouse?: "ignore"|"prioritize_hovered"|"require_hovered", wrap?: boolean }): HL.Dispatcher
            ---@field set_swallow fun(value: boolean|"true"|"false"|"toggle"): HL.Dispatcher
            ---@field kill_active fun(): HL.Dispatcher
            ---@field expand fun(arg: "expand"|"shrink"|"base"|"maximize"|"fullscreen", opts?: { fullscreen?: string }): HL.Dispatcher
            ---@field lock_tab fun(arg?: ""|"toggle"|"lock"|"unlock"): HL.Dispatcher
            ---@field equalize fun(opts?: { scope?: ""|"group"|"workspace", workspace?: boolean, recursive?: boolean }): HL.Dispatcher
            ---@field debug_nodes fun(): HL.Dispatcher
          '';
        };
    };
}
