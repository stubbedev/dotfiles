# Branch of the stubbe.lib trunk (see ../lib.nix).
# Substituters and the nixpkgs config every class instantiates pkgs with.
_: {
  stubbe.lib = {
    cache = {
      substituters = [
        "https://nix.stubbe.dev/c/default/default"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "default:6uWvXutL9cXjV3lii+Ur5ff+ArQoG4kMBKNXWrIxhHg="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "dcraw-9.28.0"
        "pnpm-10.34.0"
      ];
    };
  };
}
