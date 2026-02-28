_: {
  flake.modules.homeManager.packagesOpencode =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      latestOpencodeTag =
        (builtins.fromJSON (
          builtins.readFile (
            builtins.fetchurl "https://api.github.com/repos/anomalyco/opencode/releases/latest"
          )
        )).tag_name;
      
      # Override Bun version to 1.3.10+ for OpenCode compatibility
      bunOverride = pkgs.bun.overrideAttrs (oldAttrs: rec {
        version = "1.3.10";
        src = pkgs.fetchurl {
          url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64.zip";
          hash = "sha256-9XvAGH45Yj3nFro6OJ/aVIay175xMamAulTce3M9Lgg=";
        };
      });
      
      opencodeFlake = builtins.getFlake "github:anomalyco/opencode?ref=refs/tags/${latestOpencodeTag}";
      # Override the OpenCode package to use our custom Bun
      opencodePkg = opencodeFlake.packages.${system}.opencode.override {
        bun = bunOverride;
      };
    in
    lib.mkIf config.features.opencode {
      home.packages = [ opencodePkg ];
    };
}
