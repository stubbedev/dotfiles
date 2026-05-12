_: {
  flake.modules.nixos.plymouth =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      # nixpkgs ships `catppuccin-plymouth` hardcoded to the macchiato
      # flavor. Upstream has all four — swap the sourceRoot and install
      # paths to package the mocha variant instead, matching the Kvantum
      # theme (Catppuccin-Mocha-Mauve, modules/theme/qt.nix).
      catppuccin-mocha-plymouth = pkgs.catppuccin-plymouth.overrideAttrs (_: {
        pname = "catppuccin-mocha-plymouth";
        sourceRoot = "source/themes/catppuccin-mocha";
        installPhase = ''
          runHook preInstall
          sed -i 's:\(^ImageDir=\)/usr:\1'"$out"':' catppuccin-mocha.plymouth
          mkdir -p $out/share/plymouth/themes/catppuccin-mocha
          cp * $out/share/plymouth/themes/catppuccin-mocha
          runHook postInstall
        '';
      });

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
        themePackages = [ catppuccin-mocha-plymouth ];
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

      # Suppress the "Terminating Plymouth..." flash on VT1 between the
      # splash and SDDM. By default systemd runs plymouth-quit.service as
      # soon as multi-user.target is reached — which fires *before*
      # display-manager.service has grabbed the framebuffer, exposing the
      # bare VT for a fraction of a second. Dropping it from wantedBy
      # leaves plymouth-quit-wait.service (ordered Before=display-manager
      # via the systemd-generated ordering) as the single terminator:
      # plymouth keeps the splash up until SDDM takes the KMS scanout,
      # then quits in one step. No flash, no VT exposure.
      systemd.services.plymouth-quit.wantedBy = lib.mkForce [ ];
    };
}
