{ inputs, self, ... }:
let
  homeLib = import (self + "/lib.nix") { inherit (inputs.nixpkgs) lib; inherit self; };

  # Auto-detect NVIDIA driver version from /proc
  # Works with both proprietary and Open kernel modules
  nvidiaVersion =
    let
      nvidiaVersionPath = "/proc/driver/nvidia/version";
    in
    if builtins.pathExists (homeLib.stringToPath nvidiaVersionPath) then
      let
        data = builtins.readFile nvidiaVersionPath;
        versionMatch = builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" data;
      in
      if versionMatch != null then builtins.head versionMatch else null
    else
      null;

  # Custom nixGL overlay with NVIDIA version detection
  nixglOverlay =
    final: _prev:
    let
      isIntelX86Platform = final.stdenv.hostPlatform.system == "x86_64-linux";
      nixglArgs = {
        pkgs = final;
        enable32bits = isIntelX86Platform;
        enableIntelX86Extensions = isIntelX86Platform;
      }
      // (if nvidiaVersion != null then { inherit nvidiaVersion; } else { });
    in
    {
      nixgl = import "${inputs.nixgl}/default.nix" nixglArgs;
    };

  cshipOverlay =
    final: _prev:
    let
      src = inputs.cship;
      cargoMeta = (builtins.fromTOML (builtins.readFile "${src}/Cargo.toml")).package;
    in
    {
      cship = final.rustPlatform.buildRustPackage {
        pname = cargoMeta.name;
        version = cargoMeta.version;
        inherit src;
        cargoLock.lockFile = src + "/Cargo.lock";
        doCheck = false;
      };
    };

  # html-to-markdown ships from a polyglot workspace whose Cargo.lock is
  # gitignored, so the github tarball is unbuildable. The crates.io tarball
  # for `html-to-markdown-cli` ships its own resolved Cargo.lock for just
  # the binary subcrate — fetch that directly.
  htmlToMarkdownOverlay =
    final: _prev:
    let
      pname = "html-to-markdown-cli";
      version = "3.4.0-rc.25";
      src = final.fetchCrate {
        inherit pname version;
        hash = "sha256-aEe5qbl2UUum0bnBMVuJr6E2Yl0fsia2i0yLMnMTd2s=";
      };
    in
    {
      html-to-markdown = final.rustPlatform.buildRustPackage {
        inherit pname version src;
        cargoLock.lockFile = src + "/Cargo.lock";
        doCheck = false;
      };
    };

  # Overlay that exposes the opencode package from the opencode flake input,
  # patching out the bun version check so it builds with whatever bun nixpkgs
  # provides. The check is a build-time guard that serves no runtime purpose.
  opencodeOverlay =
    final: _prev:
    let
      system = final.stdenv.hostPlatform.system;
      opencodeFlakePkg = inputs.opencode.packages.${system}.opencode;
    in
    {
      opencode = opencodeFlakePkg.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.writeText "relax-bun-version-check.patch" ''
            --- a/packages/script/src/index.ts
            +++ b/packages/script/src/index.ts
            @@ -13,7 +13,7 @@
             // relax version requirement
             const expectedBunVersionRange = `^''${expectedBunVersion}`

            -if (!semver.satisfies(process.versions.bun, expectedBunVersionRange)) {
            +if (false) {
               throw new Error(`This script requires bun@''${expectedBunVersionRange}, but you are using bun@''${process.versions.bun}`)
             }
          '')
        ];
      });
    };
in
{
  flake.overlays = {
    nixgl = nixglOverlay;
    cship = cshipOverlay;
    html-to-markdown = htmlToMarkdownOverlay;
    opencode = opencodeOverlay;
  };
}
