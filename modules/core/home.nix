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
        username = lib.mkDefault "stubbe";
        homeDirectory = lib.mkDefault "/home/stubbe";
        stateVersion = "26.05";

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

      # home-manager reads `nix.package` only to generate and validate
      # nix.conf; it never puts that client on PATH, so every nix call kept
      # resolving to the installer's 2.34.6 in /nix/var/nix/profiles/default/bin
      # and warned "unknown experimental feature 'parallel-eval'" / "unknown
      # setting 'eval-cores'" while evaluating single-threaded. ~/.nix-profile/bin
      # comes first in sessionPath, so installing it here shadows that client.
      home.packages = lib.mkIf (config.host.platform != "nixos") [ config.nix.package ];

      nix = lib.mkIf (config.host.platform != "nixos") {
        package = lib.mkDefault inputs.determinate-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
        settings = {
          inherit (pkgs.stubbe.cache) substituters trusted-public-keys;

          # ~/.config/nix/nix.conf shadows /etc/nix/nix.conf for this user, so
          # nix-command/flakes must be repeated here or flakes stop working.
          experimental-features = [
            "nix-command"
            "flakes"
            "parallel-eval"
          ];
          eval-cores = 0;

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
