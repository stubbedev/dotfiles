_: {
  flake.modules.nixos.docs =
    { ... }:
    {
      # ~200 MB of NixOS option HTML / docbook XML lives in the system
      # closure when this is on. Disable: search.nixos.org and `man
      # configuration.nix` (still kept by documentation.man.enable)
      # cover the same ground.
      documentation.nixos.enable = false;
    };
}
