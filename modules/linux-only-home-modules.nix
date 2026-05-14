{ lib, ... }:
{
  # Secondary home-manager module bag used to organise modules that are
  # *primarily* tailored to non-NixOS hosts: nixGL-wrapped packages,
  # manual systemd unit definitions for things programs.<wm>.enable
  # provides natively on NixOS, KDE Xwayland tweaks, etc.
  #
  # In practice both `flake.modules.homeManager.*` AND this set are
  # imported by every host (standalone HM `stubbe` and NixOS
  # `stubbe-nixos`) — modules that need to no-op on NixOS self-gate via
  # `lib.mkIf (config.host.platform != "nixos") { … }`. Keep that gate
  # at the module level for clarity; this option exists only as an
  # organisational namespace, not as a load-time filter.
  #
  # Internal flake-parts attribute (no `flake.` prefix), so it doesn't
  # appear as a flake output and doesn't trigger nix flake check
  # warnings.
  options.linuxOnlyHomeModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
    description = "Home-manager modules organised separately because they mostly target non-NixOS hosts. Imported on every host; modules that should be skipped on NixOS gate internally on `config.host.platform`.";
  };
}
