# Boot: the splash screen, and the kernel log level that keeps it readable.
#
# The Plymouth theme is a package we build (pkgs.catppuccin-mocha-plymouth) and
# both halves install the same one — NixOS through boot.plymouth, non-NixOS by
# copying it into the host's /usr/share and regenerating the initramfs.
_: {
  flake.modules.nixos.boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      boot = {
        plymouth = {
          enable = true;
          package = pkgs.plymouth.override { systemd = config.boot.initrd.systemd.package; };
          theme = pkgs.stubbe.theme.plymouth;
          themePackages = [ pkgs.catppuccin-mocha-plymouth ];
        };

        # Quiet kernel + low console log level keep the splash readable instead
        # of being shouted over by dmesg lines. udev / systemd status messages
        # still reach the journal.
        kernelParams = [
          "quiet"
          "splash"
          "rd.systemd.show_status=auto"
          "rd.udev.log_level=3"
        ];
        consoleLogLevel = lib.mkDefault 3;
        initrd.verbose = false;
      };
    };

  flake.modules.homeManager.boot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Non-NixOS half of boot.plymouth above: copy the same theme package into
      # the host's /usr/share, make it the default, get `quiet splash` onto the
      # kernel cmdline, and rebuild the initramfs — each step through the
      # distro's own reversible tool.
      stubbe.setup.plymouthTheme = lib.mkIf config.features.theming {
        privileged = true;
        title = "Installing Catppuccin Mocha Plymouth theme";
        body = ''
          Install Plymouth via the host's package manager, drop the
          catppuccin-mocha theme into /usr/share/plymouth/themes, set it as
          default, ensure `quiet splash` is on the kernel cmdline, and rebuild
          every kernel's initrd so the splash appears at boot.

          Safety:
          * Theme files live in /usr/share/plymouth/themes/catppuccin-mocha and
            never overwrite an existing theme directory.
          * The kernel cmdline edit uses a reversible mechanism per distro:
            /etc/default/grub.d/ drop-in on Debian (rm + update-grub recovers),
            grubby BLS edit on Fedora (reversible with --remove-args). The main
            /etc/default/grub is never modified.
          * The initrd rebuild is delegated to the distro's native tool —
            update-initramfs -u -k all on Debian/Ubuntu, plymouth-set-default-
            theme -R (dracut) on Fedora. Both write to a temp file and rename
            atomically, so an interrupted rebuild leaves the existing initrd
            intact: worst case is "no splash next boot", not "unbootable".
          * Arch: theme files are installed but mkinitcpio.conf and bootloader
            edits are NOT automated (hook placement is fragile, bootloader
            varies). Instructions are printed instead.
        '';
        script = ''
          # Activations run with a stripped PATH; restore it so update-grub,
          # grubby and the plymouth-* helpers under /sbin are reachable.
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

          # 1. Install Plymouth. Detect on plymouthd (always present when
          #    plymouth is installed): the older plymouth-set-default-theme
          #    helper was dropped in Ubuntu 25.10, so detecting on that would
          #    re-trigger apt on every activation from questing on.
          ${pkgs.stubbe.installHostPackage {
            detect = "plymouthd";
            apt = [ "plymouth" ];
            dnf = [ "plymouth" ];
            pacman = [ "plymouth" ];
          }}

          # 2. Stage theme files — a pure copy, no boot impact yet. Patch
          #    ImageDir so plymouth finds the assets at the final /usr/share
          #    path rather than the store path baked into the theme file.
          sudo install -d -m 0755 /usr/share/plymouth/themes/catppuccin-mocha
          sudo cp -a ${pkgs.catppuccin-mocha-plymouth}/share/plymouth/themes/catppuccin-mocha/. \
            /usr/share/plymouth/themes/catppuccin-mocha/
          sudo sed -i 's|^ImageDir=.*|ImageDir=/usr/share/plymouth/themes/catppuccin-mocha|' \
            /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth

          # 3. Validate plymouth recognises the theme BEFORE touching the
          #    initrd. Ubuntu 25.10+ dropped plymouth-set-default-theme (which
          #    had a -l flag), so check for the .plymouth manifest directly. If
          #    it is missing the copy was incomplete, and we abort with no boot
          #    path modified.
          themeManifest=/usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth
          if [ ! -f "$themeManifest" ]; then
            echo "ERROR: plymouth does not recognise catppuccin-mocha after copy." >&2
            echo "  Expected manifest at $themeManifest" >&2
            ls -la /usr/share/plymouth/themes/catppuccin-mocha/ >&2 || true
            exit 1
          fi

          # 4. Default theme + kernel cmdline + initrd rebuild, per distro,
          #    detected by package manager so each uses its own native,
          #    idempotent, reversible tool.
          if command -v apt-get >/dev/null 2>&1; then
            # ----- Debian / Ubuntu -----
            # /etc/default/grub sources /etc/default/grub.d/*.cfg, so a drop-in
            # extends GRUB_CMDLINE_LINUX_DEFAULT without touching the main
            # config. Rollback = rm the drop-in + update-grub.
            ${pkgs.stubbe.installText {
              name = "50-plymouth-splash.cfg";
              target = "/etc/default/grub.d/50-plymouth-splash.cfg";
              text = ''
                # Managed by stubbe — modules/boot.nix
                GRUB_CMDLINE_LINUX_DEFAULT="''${GRUB_CMDLINE_LINUX_DEFAULT} quiet splash"
              '';
            }}
            if ! sudo update-grub; then
              echo "ERROR: update-grub failed after dropping the plymouth-splash cfg." >&2
              echo "  Removing the drop-in and re-running update-grub to restore." >&2
              sudo rm -f /etc/default/grub.d/50-plymouth-splash.cfg
              sudo update-grub || true
              exit 1
            fi

            # Debian/Ubuntu ship default.plymouth as an alternatives-managed
            # symlink, and 25.10 dropped the helper that used to wrap this.
            # --install is idempotent; --set forces the selection.
            sudo update-alternatives --install \
              /usr/share/plymouth/themes/default.plymouth default.plymouth \
              "$themeManifest" 100
            sudo update-alternatives --set default.plymouth "$themeManifest"

            # -k all rebuilds EVERY kernel's initrd, not just the
            # default-symlinked one: without it, booting a non-default kernel
            # keeps the previous theme and the splash silently does not change.
            if ! sudo update-initramfs -u -k all; then
              echo "ERROR: initrd rebuild failed. Existing initrd untouched (update-initramfs writes atomically)." >&2
              echo "  Next boot should still work; the splash just won't render." >&2
              exit 1
            fi

          elif command -v dnf >/dev/null 2>&1; then
            # ----- Fedora -----
            # grubby edits each kernel's BLS entry directly, no
            # /etc/default/grub regeneration. Idempotent, reversible via
            # --remove-args.
            if command -v grubby >/dev/null 2>&1; then
              sudo grubby --update-kernel=ALL --args="quiet splash" >/dev/null
            else
              echo "WARN: grubby missing on this Fedora host; skipping kernel cmdline edit." >&2
              echo "  Add 'quiet splash' to your boot loader entries manually." >&2
            fi

            if ! sudo plymouth-set-default-theme -R catppuccin-mocha; then
              echo "ERROR: dracut rebuild failed. Existing initrd untouched." >&2
              echo "  Next boot should still work; the splash just won't render." >&2
              exit 1
            fi

          elif command -v pacman >/dev/null 2>&1; then
            # ----- Arch -----
            # Needs (a) the `plymouth` hook in /etc/mkinitcpio.conf BEFORE
            # `udev`, and (b) `quiet splash` on the kernel cmdline, whose
            # location depends on the bootloader. Both are too host-variable to
            # automate safely, so print the steps; theme files are already in
            # place above.
            cat >&2 <<'EOF'

            INFO: Theme files installed. Three manual steps remain on Arch:

              1. sudo plymouth-set-default-theme catppuccin-mocha

              2. Add 'plymouth' to the HOOKS array in /etc/mkinitcpio.conf
                 BEFORE 'udev' (and before 'encrypt'/'sd-encrypt' if used).
                 Then: sudo mkinitcpio -P

              3. Add 'quiet splash' to your kernel cmdline:
                 - GRUB:         append to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub,
                                 then 'sudo grub-mkconfig -o /boot/grub/grub.cfg'
                 - systemd-boot: edit /boot/loader/entries/*.conf, append to 'options'

              Wiki: https://wiki.archlinux.org/title/Plymouth
            EOF

          else
            echo "Unsupported distribution (no apt-get/dnf/pacman). Theme files staged but boot integration skipped." >&2
          fi

          # Unmask plymouth-quit.service if a previous activation masked it.
          # Masking that unit deadlocks boot: it is what runs `plymouth quit`,
          # and plymouth-quit-wait.service only blocks on plymouth's exit — so
          # without the quit signal the splash never clears and the display
          # manager stays gated behind it.
          if command -v systemctl >/dev/null 2>&1 \
             && [ "$(systemctl is-enabled plymouth-quit.service 2>/dev/null)" = "masked" ]; then
            sudo systemctl unmask plymouth-quit.service
          fi
        '';
      };
    };
}
