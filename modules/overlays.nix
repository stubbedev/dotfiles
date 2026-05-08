{ inputs, ... }:
let
  # Auto-detect NVIDIA driver version from /proc. Works with both
  # proprietary and Open kernel modules. Requires --impure (the flake
  # already runs that way) so /proc reads succeed.
  nvidiaVersion =
    let
      nvidiaVersionPath = /. + "/proc/driver/nvidia/version";
    in
    if builtins.pathExists nvidiaVersionPath then
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

in
{
  flake.overlays = {
    nixgl = nixglOverlay;
    cship = cshipOverlay;
  };
}
