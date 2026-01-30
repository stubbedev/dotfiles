{ ... }:
{
  flake.modules.homeManager.packagesOpencode = { pkgs, lib, config, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      latestOpencodeTag =
        (builtins.fromJSON (builtins.readFile (builtins.fetchurl
          "https://api.github.com/repos/anomalyco/opencode/releases/latest"))).tag_name;
      opencodeFlake = builtins.getFlake
        "github:anomalyco/opencode?ref=refs/tags/${latestOpencodeTag}";
      opencodePkg = opencodeFlake.packages.${system}.opencode;
    in
    lib.mkIf config.features.opencode {
      home.packages = [ opencodePkg ];
    };
}
