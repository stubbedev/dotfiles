# Branch of the stubbe.lib trunk (see ../lib.nix).
# Substituters and the nixpkgs config every class instantiates pkgs with.
_: {
  stubbe.lib = {
    cache = {
      # xilo (xilos.dev) first: self-hosted cache is preferred, then
      # upstream and nix-community.
      substituters = [
        "https://xilos.dev/c/stubbedev/main"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "xilos.dev/stubbedev/main-1:397R6S49v/FSvP+mZ3HlKrVN1KXhgzHIEIHxA/UuG6Y="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "dcraw-9.28.0"
      ];
    };
  };
}
