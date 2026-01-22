{
  description = "Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixgl.url = "github:nix-community/nixGL";

    # Use official Hyprland flake for better plugin compatibility
    # Use v0.53.0 which is the latest stable release
    hyprland.url =
      "git+https://github.com/hyprwm/Hyprland?ref=v0.53.0&submodules=1";

    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      url =
        "github:outfoxxed/hy3?ref=hl0.53.0"; # Use hl0.53.0 tag to match Hyprland v0.53.0
      inputs.hyprland.follows =
        "hyprland"; # Use the same hyprland as our main input
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { ... }@inputs:
    let
      system = "x86_64-linux";

      # Auto-detect NVIDIA driver version from /proc
      # Works with both proprietary and Open kernel modules
      nvidiaVersion =
        let
          nvidiaVersionPath = "/proc/driver/nvidia/version";
        in
        if builtins.pathExists (builtins.toPath nvidiaVersionPath) then
          let
            data = builtins.readFile nvidiaVersionPath;
            # Match version after "x86_64" (works for Open Kernel Module)
            # or after "Module" (works for proprietary driver)
            versionMatch =
              builtins.match ".*x86_64[[:space:]]+([0-9.]+)[[:space:]]+.*" data;
          in
          if versionMatch != null then builtins.head versionMatch else null
        else
          null;

      # Custom nixGL overlay with NVIDIA version detection
      nixglOverlay = final: prev:
        let
          isIntelX86Platform = final.stdenv.hostPlatform.system
            == "x86_64-linux";
          # Build nixGL arguments - only include nvidiaVersion if detected
          nixglArgs = {
            pkgs = final;
            enable32bits = isIntelX86Platform;
            enableIntelX86Extensions = isIntelX86Platform;
          } // (if nvidiaVersion != null then { nvidiaVersion = nvidiaVersion; } else {});
        in {
          nixgl = import "${inputs.nixgl}/default.nix" nixglArgs;
        };
    in {
      homeConfigurations."stubbe" =
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              allowUnfreePredicate = (_: true);
              allowInsecure = true;
              allowInsecurePredicate = (_: true);
            };
            overlays = [ nixglOverlay ];
          };
          extraSpecialArgs = inputs;
          modules = [ ./home.nix ];
        };
    };
}
