# The home-manager baseline every host shares: who the user is, where their
# home is, what is on PATH, and how user-mode `nix` finds our caches.
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
        # unstable is still 26.05), tripping HM's version-mismatch warning.
        # The skew is intentional and harmless here.
        enableNixpkgsReleaseCheck = false;

        # User-level PATH. Keep this minimal — every tool we use lands in
        # config.home.profileDirectory/bin via Nix. Two exceptions:
        #   - ~/.config/composer/vendor/bin: PHP composer global packages
        #   - ~/.local/share/pnpm:           pnpm global installs (PNPM_HOME)
        # Tool-managed dirs (~/.cargo/bin, ~/.bun/bin, ~/.go/bin, …) stay off
        # PATH so they cannot shadow the Nix-pinned versions.
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

      # Non-NixOS only: let home-manager's genericLinux support fix up
      # XDG_DATA_DIRS for the host's desktop, and hand it our nixGL set.
      targets.genericLinux = lib.mkIf (config.host.platform != "nixos") {
        enable = true;
        nixGL.packages = pkgs.nixgl;
      };

      # Daemon-level substituters live in modules/nix.nix on NixOS hosts
      # (useGlobalPkgs makes HM read those same overlaid pkgs, and only the
      # daemon's substituters actually fetch). On standalone HM we set them
      # here so user-mode `nix` calls hit the same caches.
      nix = lib.mkIf (config.host.platform != "nixos") {
        package = lib.mkDefault pkgs.nix;
        settings = { inherit (pkgs.stubbe.cache) substituters trusted-public-keys; };
      };
    };

  # The NixOS side of the same baseline: install the home-manager module and
  # point it at the shared pkgs, so every `flake.modules.homeManager.*` aspect
  # evaluates against the identical package set on both targets.
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
