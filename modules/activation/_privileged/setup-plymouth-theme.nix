_: {
  enableIf = { config, ... }: config.features.theming;
  args =
    { pkgs, homeLib, ... }:
    let
      # nixpkgs ships catppuccin-plymouth hardcoded to the macchiato
      # flavor. Upstream has all four — swap sourceRoot + install paths
      # to package mocha, matching the Kvantum/GTK Catppuccin Mocha set.
      theme = pkgs.catppuccin-plymouth.overrideAttrs (_: {
        pname = "catppuccin-mocha-plymouth";
        sourceRoot = "source/themes/catppuccin-mocha";
        installPhase = ''
          runHook preInstall
          mkdir -p $out/share/plymouth/themes/catppuccin-mocha
          cp * $out/share/plymouth/themes/catppuccin-mocha
          runHook postInstall
        '';
      });
    in
    homeLib.mkInstallPrompt {
      subject = "Catppuccin Mocha Plymouth theme";
      body = ''
        Install Plymouth via the host's package manager, drop the
        catppuccin-mocha theme into /usr/share/plymouth/themes, set it
        as default, ensure `quiet splash` is on the kernel cmdline, and
        rebuild the initrd so the splash appears at boot.

        Safety:
        * Theme files live in /usr/share/plymouth/themes/catppuccin-mocha
          and never overwrite an existing theme directory.
        * Kernel cmdline edit uses a reversible mechanism per distro:
          /etc/default/grub.d/ drop-in on Debian (rm + update-grub
          recovers), grubby BLS edit on Fedora (reversible with
          --remove-args). The main /etc/default/grub is never modified.
        * Initrd rebuild is delegated to plymouth-set-default-theme -R,
          which calls update-initramfs/dracut. Both write the new image
          to a temp file and rename atomically — a failed rebuild
          leaves the existing initrd intact, so worst case is "no
          splash next boot" rather than "unbootable".
        * Arch: theme files are installed but mkinitcpio.conf and
          bootloader edits are NOT automated (hook placement is
          fragile, bootloader varies). Instructions are printed.

        On NixOS, modules/nixos/plymouth.nix handles this declaratively;
        this activation is gated off there.
      '';
      actionScript = ''
        # Activations run with a stripped PATH; restore so commands
        # under /sbin and /usr/sbin (update-grub, grubby, plymouth-*)
        # are reachable.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        # ---------------------------------------------------------------
        # 1. Install Plymouth via the host package manager.
        # ---------------------------------------------------------------
        ${homeLib.installHostPackage {
          detect = "plymouth-set-default-theme";
          apt = [ "plymouth" ];
          dnf = [ "plymouth" ];
          pacman = [ "plymouth" ];
        }}

        # ---------------------------------------------------------------
        # 2. Stage theme files. Pure file copy — no boot impact yet.
        #    Patch ImageDir so plymouth finds the assets at the final
        #    /usr/share path instead of the nix store path baked into
        #    the upstream theme file.
        # ---------------------------------------------------------------
        sudo install -d -m 0755 /usr/share/plymouth/themes/catppuccin-mocha
        sudo cp -a ${theme}/share/plymouth/themes/catppuccin-mocha/. \
          /usr/share/plymouth/themes/catppuccin-mocha/
        sudo sed -i 's|^ImageDir=.*|ImageDir=/usr/share/plymouth/themes/catppuccin-mocha|' \
          /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth

        # ---------------------------------------------------------------
        # 3. Validate plymouth recognises the theme BEFORE touching the
        #    initrd. -l lists every theme plymouth can find under
        #    /usr/share/plymouth/themes. If catppuccin-mocha isn't here,
        #    the copy step was incomplete and we abort without any boot
        #    path modification.
        # ---------------------------------------------------------------
        if ! plymouth-set-default-theme -l 2>/dev/null | grep -qx catppuccin-mocha; then
          echo "ERROR: plymouth does not recognise catppuccin-mocha after copy." >&2
          echo "  Theme dir contents:" >&2
          ls -la /usr/share/plymouth/themes/catppuccin-mocha/ >&2 || true
          exit 1
        fi

        # ---------------------------------------------------------------
        # 4. Set the default theme symlink. No initrd touch yet —
        #    this only updates /usr/share/plymouth/themes/default.plymouth
        #    (or distro equivalent). Trivially reversible.
        # ---------------------------------------------------------------
        sudo plymouth-set-default-theme catppuccin-mocha

        # ---------------------------------------------------------------
        # 5. Distro-specific kernel cmdline + initrd rebuild.
        #    Detect distro by package manager so we use each distro's
        #    native, idempotent, reversible tool.
        # ---------------------------------------------------------------
        if command -v apt-get >/dev/null 2>&1; then
          # ----- Debian / Ubuntu -----
          # /etc/default/grub sources /etc/default/grub.d/*.cfg, so a
          # drop-in is the safe way to extend GRUB_CMDLINE_LINUX_DEFAULT
          # without touching the main config. Rollback = rm the drop-in
          # + update-grub. We never sed the main file.
          sudo install -d -m 0755 /etc/default/grub.d
          ${homeLib.installSystemFile {
            target = "/etc/default/grub.d/50-plymouth-splash.cfg";
            content = ''
              # Managed by stubbedev dotfiles —
              # modules/activation/_privileged/setup-plymouth-theme.nix
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

          # plymouth-set-default-theme -R on Debian/Ubuntu runs
          # update-initramfs -u, which writes to a tmp file and renames
          # atomically. The existing /boot/initrd.img-* stays put if the
          # rebuild dies mid-way.
          if ! sudo plymouth-set-default-theme -R catppuccin-mocha; then
            echo "ERROR: initrd rebuild failed. Existing initrd untouched (update-initramfs writes atomically)." >&2
            echo "  Next boot should still work; the splash just won't render. Recover by booting an older kernel from GRUB if needed." >&2
            exit 1
          fi

        elif command -v dnf >/dev/null 2>&1; then
          # ----- Fedora -----
          # grubby edits the BLS entry for each kernel directly; no
          # /etc/default/grub regeneration needed. Idempotent and
          # reversible via --remove-args.
          if command -v grubby >/dev/null 2>&1; then
            sudo grubby --update-kernel=ALL --args="quiet splash" >/dev/null
          else
            echo "WARN: grubby missing on this Fedora host; skipping kernel cmdline edit." >&2
            echo "  Add 'quiet splash' to your boot loader entries manually." >&2
          fi

          # dracut (called by plymouth-set-default-theme -R on Fedora)
          # writes initrd atomically.
          if ! sudo plymouth-set-default-theme -R catppuccin-mocha; then
            echo "ERROR: dracut rebuild failed. Existing initrd untouched." >&2
            echo "  Next boot should still work; the splash just won't render. Recover by booting an older kernel from GRUB if needed." >&2
            exit 1
          fi

        elif command -v pacman >/dev/null 2>&1; then
          # ----- Arch -----
          # Arch needs (a) `plymouth` hook in /etc/mkinitcpio.conf
          # BEFORE `udev`, and (b) `quiet splash` on the kernel cmdline
          # (location depends on bootloader: GRUB, systemd-boot, rEFInd,
          # …). Both edits are too host-variable to automate safely;
          # print instructions instead. Theme files + default-theme
          # symlink are already in place above, so once the user
          # finishes the two steps they get the splash.
          echo "" >&2
          echo "INFO: Theme files installed. Two manual steps remain on Arch:" >&2
          echo "" >&2
          echo "  1. Add 'plymouth' to the HOOKS array in /etc/mkinitcpio.conf" >&2
          echo "     BEFORE 'udev' (and BEFORE 'encrypt'/'sd-encrypt' if you use them)." >&2
          echo "     Then run: sudo mkinitcpio -P" >&2
          echo "" >&2
          echo "  2. Add 'quiet splash' to your kernel cmdline:" >&2
          echo "     - GRUB:        append to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub," >&2
          echo "                    then 'sudo grub-mkconfig -o /boot/grub/grub.cfg'" >&2
          echo "     - systemd-boot: edit /boot/loader/entries/*.conf, append to 'options'" >&2
          echo "" >&2
          echo "  Wiki: https://wiki.archlinux.org/title/Plymouth" >&2

        else
          echo "Unsupported distribution (no apt-get/dnf/pacman). Theme files staged but boot integration skipped." >&2
        fi
      '';
    };
}
