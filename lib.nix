# Shared home-manager helper library, aggregated from domain files under
# lib/.
#
# Conventions:
#   * Each domain file takes its dependencies as explicit arguments — no
#     implicit closures over this file's bindings.
#   * Callers may import lib.nix WITHOUT pkgs (NixOS modules do), so any
#     builder that needs pkgs guards lazily inside its own body via a
#     local `requirePkgs` that throws only when the builder is called.
#   * Everything exported here stays flat under homeLib.*; domain files
#     never leak their internal structure to callers.
{
  lib,
  pkgs ? null,
  systemInfo ? null,
  self,
  isNixOS ? false,
  ...
}:
let
  templates = import ./lib/templates.nix { inherit lib; };
  xdgConfigs = import ./lib/xdg-configs.nix {
    inherit lib self;
  };
  secrets = import ./lib/secrets.nix { inherit self; };
  systemInstall = import ./lib/system-install.nix { inherit lib; };
  scriptBins = import ./lib/script-bins.nix {
    inherit self pkgs substituteFile;
  };
  jsonPatches = import ./lib/json-patches.nix { inherit pkgs; };
  liveLinks = import ./lib/live-links.nix { };
  sudoPrompts = import ./lib/sudo-prompts.nix { inherit lib; };
  sessionPaths = import ./lib/session-paths.nix { inherit lib; };

  gfxLib = import ./lib/gfx.nix {
    inherit
      lib
      pkgs
      systemInfo
      isNixOS
      ;
  };
  wrappedPackages = import ./lib/wrapped-packages.nix {
    inherit lib pkgs;
    inherit (gfxLib) gfxName gfxExe;
  };

  inherit (templates) substituteFile;
in
rec {
  # ============================================================
  # GFX wrappers (nixGL) — see lib/gfx.nix
  # ============================================================

  inherit (gfxLib)
    gfx
    gfxName
    gfxExe
    gfxDirectWithDrivers
    gfxDriverLibs
    ;

  # ============================================================
  # Color palette
  # ============================================================

  # Catppuccin Mocha (hex, no #). Single source of truth; see lib/colors.nix.
  catppuccinMocha = import ./lib/colors.nix;

  # ============================================================
  # XDG config sources — see lib/xdg-configs.nix
  # ============================================================

  inherit (xdgConfigs)
    xdgSource
    xdgSources
    xdgContent
    ;

  # ============================================================
  # SOPS secrets — see lib/secrets.nix
  # ============================================================

  inherit (secrets) mkBinarySecret;

  # ============================================================
  # Template substitution — see lib/templates.nix
  # ============================================================

  inherit substituteFile;

  # ============================================================
  # System file installation (privileged activations) — see
  # lib/system-install.nix
  # ============================================================

  inherit (systemInstall)
    installSystemFile
    installHostPackage
    installPolkitRule
    installApparmorProfile
    requireCommand
    requirePath
    mkAppArmorSetup
    ;

  # ============================================================
  # Script binaries (live in config.home.profileDirectory/bin/) — see
  # lib/script-bins.nix
  # ============================================================

  inherit (scriptBins) mkScriptBin;

  # ============================================================
  # Canonical URL of the local new-tab / new-window page. `srv` serves it
  # as a static site at https://start.local (registered once with
  # `srv add` — see the README). A file:// page can't be used: Tridactyl's
  # `set newtab` double-opens file:// URLs (tridactyl#530); serving over
  # https also gives one URL that works for both Firefox and Chrome.
  # Shared so tridactylrc, the Firefox Homepage policy and the Chrome
  # enterprise policy all agree.
  # ============================================================

  browserNewtabUrl = "https://start.local/";

  # ============================================================
  # Live symlinks/copies (point $HOME paths at ~/.stubbe/src/<y>) — see
  # lib/live-links.nix
  # ============================================================

  inherit (liveLinks)
    mkLiveSymlink
    mkLiveCopy
    ;

  # ============================================================
  # JSON state-file mutators — see lib/json-patches.nix
  # ============================================================

  inherit (jsonPatches)
    mergeJsonPatch
    setJsonKey
    ;

  # ============================================================
  # Sudo prompt scaffolding — see lib/sudo-prompts.nix
  # ============================================================

  inherit (sudoPrompts)
    sudoPromptScript
    mkInstallPrompt
    ;

  # ============================================================
  # Compositor session-path resolution — see lib/session-paths.nix
  # ============================================================

  inherit (sessionPaths) resolveSessionPaths;

  # ============================================================
  # Wrapped-package bundling — see lib/wrapped-packages.nix
  # ============================================================

  inherit (wrappedPackages) mkWrappedPackage;
}
