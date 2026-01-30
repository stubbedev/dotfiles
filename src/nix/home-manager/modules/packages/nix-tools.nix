{ ... }:
{
  flake.modules.homeManager.packagesNixTools = { pkgs, ... }: {
    home.packages = with pkgs; [
      nix-zsh-completions
      nh
      pass
      age
      cachix
      nixd
      nixdoc
    ];
  };
}
