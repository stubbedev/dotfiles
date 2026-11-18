{ config, inputs, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
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

      # home-configuration.nix(5). Its options.json is built by nixpkgs'
      # `nixosOptionsDoc`, which `unsafeDiscardStringContext`s the options
      # JSON; home-manager's docs only rewrite declaration paths under its own
      # tree, so nixpkgs' lib/modules/generic/meta-maintainers.nix leaks
      # through as a bare store path and every eval warns about a derivation
      # with no proper context. `phix mcp` covers option lookup, so drop it.
      manual.manpages.enable = false;

      home = {
        # mkDefault so the NixOS bridge can set these from
        # users.users.<name>.home without a priority conflict.
        username = lib.mkDefault pkgs.stubbe.userName;
        homeDirectory = lib.mkDefault "/home/${pkgs.stubbe.userName}";
        stateVersion = "26.05";

        enableNixpkgsReleaseCheck = false;

        sessionPath = [
          config.stubbe.paths.nixBin
          "$HOME/.local/bin"
        ];
      };

      # home-manager defaults `nix.package` to null, and its nix module reads
      # it as `config.nix.package` for nix-env/nix-collect-garbage.
      nix.package = lib.mkDefault pkgs.nix;
    };

  flake.modules.nixos.home =
    { config, lib, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.${config.host.primaryUser} = lib.mkIf config.host.installed {
          imports = builtins.attrValues homeModules;
          host = config.host.sharedFacts // {
            platform = "nixos";
          };
        };
      };
    };
}
