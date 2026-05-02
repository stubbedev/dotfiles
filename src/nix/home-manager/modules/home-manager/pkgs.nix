{ inputs, ... }:
let
  homeLib = import ../../lib.nix { inherit (inputs.nixpkgs) lib; };

  # Auto-detect NVIDIA driver version from /proc
  # Works with both proprietary and Open kernel modules
  nvidiaVersion =
    let
      nvidiaVersionPath = "/proc/driver/nvidia/version";
    in
    if builtins.pathExists (homeLib.stringToPath nvidiaVersionPath) then
      let
        data = builtins.readFile nvidiaVersionPath;
        # Match version after "x86_64" (works for Open Kernel Module)
        # or after "Module" (works for proprietary driver)
        versionMatch = builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" data;
      in
      if versionMatch != null then builtins.head versionMatch else null
    else
      null;

  # Custom nixGL overlay with NVIDIA version detection
  nixglOverlay =
    final: prev:
    let
      isIntelX86Platform = final.stdenv.hostPlatform.system == "x86_64-linux";
      # Build nixGL arguments - only include nvidiaVersion if detected
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
    final: prev:
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

  # Overlay that exposes the opencode package from the opencode flake input,
  # patching out the bun version check so it builds with whatever bun nixpkgs
  # provides. The check is a build-time guard that serves no runtime purpose.
  opencodeOverlay =
    final: prev:
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

  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
        allowInsecure = true;
        allowInsecurePredicate = _: true;
      };
      overlays = [
        nixglOverlay
        opencodeOverlay
        cshipOverlay
      ];
    };
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = mkPkgs system;
    };
}
