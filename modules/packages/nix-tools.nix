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
        # nh ships unconditionally via modules/home/scripts.nix (hm depends
        # on it); no need to list it again behind the development gate.
        pass
        age
        cachix
        attic-client
        nixd
        nixdoc
        nil
      ];
    };
}
