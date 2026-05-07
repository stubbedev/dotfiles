_: {
  # Project-wide feature profile for stubbe's machines. modules/features.nix
  # defines the option set with default = true everywhere; this module pins
  # the values that should differ from the upstream defaults across every
  # host (HM-only `stubbe`, NixOS `stubbe-nixos`, and the live ISO). Set
  # via lib.mkDefault so a future minimal/CI host can still override.
  flake.modules.homeManager.featureDefaults =
    { lib, ... }:
    {
      features.php = lib.mkDefault false;
    };
}
