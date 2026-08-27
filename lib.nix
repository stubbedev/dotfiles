# TEMPORARY migration shim — see modules/core/compat.nix.
#
# The old flat `homeLib.*` surface, re-expressed on top of `pkgs.stubbe` and
# `config.stubbe.gfx`. Aspects still naming `homeLib` keep working while they
# are migrated one at a time. Delete this file and lib/ once none do.
{
  lib,
  pkgs,
  self,
  gfx,
  ...
}:
let
  xdgConfigs = import ./lib/xdg-configs.nix { inherit lib self; };
  systemInstall = import ./lib/system-install.nix { inherit lib; };
  scriptBins = import ./lib/script-bins.nix {
    inherit self pkgs;
    inherit (templates) substituteFile;
  };
  templates = import ./lib/templates.nix { inherit lib; };
  jsonPatches = import ./lib/json-patches.nix { inherit pkgs; };
  liveLinks = import ./lib/live-links.nix { };
  sudoPrompts = import ./lib/sudo-prompts.nix { inherit lib; };
  sessionPaths = import ./lib/session-paths.nix { inherit lib; };
in
{
  # Graphics wrappers, now owned by modules/core/gfx.nix.
  gfx = gfx.wrap;
  gfxName = gfx.wrapAs;
  gfxExe = gfx.wrapExe;
  gfxDirectWithDrivers = gfx.wrapDirect;
  gfxDriverLibs = gfx.withDriverLibs;
  mkWrappedPackage = gfx.bundle;

  # Data, now owned by flake.lib / pkgs.stubbe.
  catppuccinMocha = pkgs.stubbe.colors;
  browserNewtabUrl = pkgs.stubbe.newtabUrl;
  mkBinarySecret = pkgs.stubbe.secret;

  inherit (templates) substituteFile;
  inherit (xdgConfigs) xdgSource xdgSources xdgContent;
  inherit (systemInstall)
    installSystemFile
    installHostPackage
    installPolkitRule
    installApparmorProfile
    requireCommand
    requirePath
    mkAppArmorSetup
    ;
  inherit (scriptBins) mkScriptBin;
  inherit (liveLinks) mkLiveSymlink mkLiveCopy;
  inherit (jsonPatches) mergeJsonPatch setJsonKey;
  inherit (sudoPrompts) sudoPromptScript mkInstallPrompt;
  inherit (sessionPaths) resolveSessionPaths;
}
