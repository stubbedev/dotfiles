_: {
  flake.modules.homeManager.packagesNixTools =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.development {
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
