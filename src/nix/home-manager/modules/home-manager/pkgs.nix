{ inputs, ... }:
let
  homeLib = import ../../lib.nix { inherit (inputs.nixpkgs) lib; };

  # Auto-detect NVIDIA driver version from /proc
  # Works with both proprietary and Open kernel modules
  nvidiaVersion =
    let
      nvidiaVersionPath = "/proc/driver/nvidia/version";
    in
    if builtins.pathExists (homeLib.toPath nvidiaVersionPath) then
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
      overlays = [ nixglOverlay ];
    };
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = mkPkgs system;
    };
}
