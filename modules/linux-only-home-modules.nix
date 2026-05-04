{ lib, ... }:
{
  # Home-manager modules that only make sense on non-NixOS distros (carrying
  # nixGL wrappers, manual systemd unit definitions, KDE Xwayland tweaks, etc.).
  # Non-NixOS hosts import both this set and `flake.modules.homeManager.*`.
  # The NixOS host skips this set — those concerns are handled natively
  # via NixOS modules (programs.<wm>.enable, services.displayManager, ...).
  #
  # Internal flake-parts attribute (no `flake.` prefix), so it doesn't appear
  # as a flake output and doesn't trigger nix flake check warnings.
  options.linuxOnlyHomeModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
    description = "Home-manager modules to import only on non-NixOS hosts.";
  };
}
