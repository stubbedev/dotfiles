{ self, ... }:
{
  flake.modules.nixos.plymouth =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      # Shared with modules/activation/_privileged/setup-plymouth-theme.nix.
      inherit (import (self + "/lib/plymouth.nix") { inherit pkgs; })
        catppuccinMochaPlymouth
        ;

      # Fedora carries this patch against the same 24.004.60 we use:
      # https://src.fedoraproject.org/rpms/plymouth — file
      # 0001-ply-device-manager-Revert-Fall-back-to-text-plugin-i.patch
      # tracks https://gitlab.freedesktop.org/plymouth/plymouth/-/merge_requests/319.
      #
      # Reverts upstream commit 03842d5201e4486fe62635c7b470eb94696f985d
      # ("Fall back to text plugin if no renderers installed"). That
      # change makes plymouth commit to text mode on the *first* failed
      # DRM probe — which is exactly what loses on nvidia-drm: the
      # initial udev change event for /dev/dri/card0 arrives before any
      # monitor connector has a CRT controller bound, plymouth's
      # `query_device` returns "Could not initialize heads", and the
      # text-mode fallback is committed. By the time DeviceTimeout
      # elapses and the second enumeration succeeds (controller bound,
      # mode 2560x1440 found), the splash plugin is already `details`
      # (text). Verified end-to-end via /var/log/plymouth-debug.log:
      # see the "outputs unchanged → Could not initialize heads" at
      # 00:00:03.426 vs "Using controller 62 for connector 142 →
      # outputs changed" at 00:00:09.330 in the same boot.
      #
      # With the patch, plymouth ignores the initial failure and waits
      # for DeviceTimeout (8s by default) to re-enumerate, by which
      # time nvidia has bound the controller and a graphical splash
      # loads.
      patchedPlymouth =
        (pkgs.plymouth.override { systemd = config.boot.initrd.systemd.package; }).overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [ ./plymouth-revert-text-fallback.patch ];
          });
    in
    {
      boot.plymouth = {
        enable = true;
        package = patchedPlymouth;
        theme = "catppuccin-mocha";
        themePackages = [ catppuccinMochaPlymouth ];
      };

      # Quiet kernel + low console log level keep the splash readable
      # instead of being shouted over by dmesg lines. udev / systemd
      # status messages still hit the journal.
      boot.kernelParams = [
        "quiet"
        "splash"
        "rd.systemd.show_status=auto"
        "rd.udev.log_level=3"
      ];
      boot.consoleLogLevel = lib.mkDefault 3;
      boot.initrd.verbose = false;
    };
}
