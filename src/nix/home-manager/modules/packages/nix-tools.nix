{ ... }:
{
  flake.modules.homeManager.packages.nixTools = { pkgs, ... }: {
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
