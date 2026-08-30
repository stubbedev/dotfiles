{ inputs, ... }:
{
  flake.modules.homeManager.home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.home-manager.enable = true;

      home = {
        # mkDefault so the NixOS bridge can set these from
        # users.users.<name>.home without a priority conflict; on standalone HM
        # these defaults are the only definitions.
        username = lib.mkDefault "stubbe";
        homeDirectory = lib.mkDefault "/home/stubbe";
        stateVersion = "26.05";

        # We track nixpkgs nixos-unstable + home-manager master. HM master
        # bumps its release string ahead of unstable (e.g. HM 26.11 while
        enableNixpkgsReleaseCheck = false;

        sessionPath = [
          config.stubbe.paths.nixBin
          "$HOME/.local/bin"
          "$HOME/.config/composer/vendor/bin"
          "$HOME/.local/share/pnpm"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/sbin"
        ];
      };

      targets.genericLinux = lib.mkIf (config.host.platform != "nixos") {
        enable = true;
        nixGL.packages = pkgs.nixgl;
      };

      nix = lib.mkIf (config.host.platform != "nixos") {
        package = lib.mkDefault pkgs.nix;
        settings = {
          inherit (pkgs.stubbe.cache) substituters trusted-public-keys;

          max-jobs = "auto";
          cores = 2;

          download-buffer-size = 128 * 1024 * 1024;
        };
      };
    };

  flake.modules.nixos.home =
    { ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    };
}
