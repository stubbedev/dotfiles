_: {
  enableIf = { config, ... }: config.features.theming;
  args =
    { pkgs, homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "SDDM with Catppuccin Mocha Mauve + Vimix cursor";
      body = ''
        Install SDDM + weston (used as the Wayland greeter compositor,
        matching the NixOS host), drop the catppuccin-mocha-mauve theme
        into /usr/share/sddm/themes and the Vimix-cursors theme into
        /usr/share/icons, then make SDDM the system display manager.

        The display-manager swap:
        * Disables any other DM that's currently enabled (gdm, gdm3,
          lightdm, lxdm, xdm) — `systemctl disable` only, no stop.
        * Rewrites /etc/systemd/system/display-manager.service (the
          generic alias systemd uses) to point at sddm.service.
        * On Debian/Ubuntu, also rewrites /etc/X11/default-display-manager
          so the debconf path stays in sync (otherwise a future
          apt-upgrade can flip it back).
        * Sets graphical.target as the default boot target.
        * Does NOT restart display-manager — that would log out the
          current session. Takes effect on next reboot.

        On NixOS, modules/nixos/greetd.nix configures all of this
        declaratively; this activation is gated off there.
      '';
      actionScript = ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        # ---------------------------------------------------------------
        # 1. Install SDDM + weston via the host package manager.
        #    weston is the Wayland compositor SDDM uses for the greeter
        #    (matches the NixOS sddm wayland.enable path which calls
        #    `weston --shell=kiosk`). Much lighter than kwin and
        #    available on all three distros.
        # ---------------------------------------------------------------
        ${homeLib.installHostPackage {
          detect = "sddm";
          apt = [ "sddm" "weston" ];
          dnf = [ "sddm" "weston" ];
          pacman = [ "sddm" "weston" ];
        }}

        # ---------------------------------------------------------------
        # 2. Stage theme + cursor files. Pure file copies — no service
        #    state changes yet, so trivially reversible.
        # ---------------------------------------------------------------
        sudo install -d -m 0755 /usr/share/sddm/themes/catppuccin-mocha-mauve
        sudo cp -a ${pkgs.catppuccin-sddm}/share/sddm/themes/catppuccin-mocha-mauve/. \
          /usr/share/sddm/themes/catppuccin-mocha-mauve/

        sudo install -d -m 0755 /usr/share/icons
        sudo cp -a ${pkgs.vimix-cursors}/share/icons/Vimix-cursors \
          /usr/share/icons/

        # ---------------------------------------------------------------
        # 3. SDDM config + greeter compositor config. Both as drop-ins —
        #    /etc/sddm.conf is left untouched, so removing our snippet
        #    restores stock SDDM behavior. SessionDir points at the
        #    location the Hyprland session entry already lands
        #    (modules/activation/_privileged/setup-hyprland-sddm-session.nix
        #    via mkSddmSession writes to /usr/share/wayland-sessions).
        # ---------------------------------------------------------------
        sudo install -d -m 0755 /etc/sddm.conf.d
        ${homeLib.installSystemFile {
          target = "/etc/sddm.conf.d/10-stubbedev.conf";
          content = ''
            # Managed by stubbedev dotfiles —
            # modules/activation/_privileged/setup-sddm.nix
            [General]
            DisplayServer=wayland

            [Wayland]
            CompositorCommand=weston --shell=kiosk -c /etc/sddm-weston.ini
            SessionDir=/usr/share/wayland-sessions
            EnableHiDPI=true

            [Theme]
            Current=catppuccin-mocha-mauve
            CursorTheme=Vimix-cursors
            CursorSize=24
          '';
        }}
        ${homeLib.installSystemFile {
          target = "/etc/sddm-weston.ini";
          content = ''
            # Managed by stubbedev dotfiles —
            # modules/activation/_privileged/setup-sddm.nix
            [keyboard]
            keymap_layout=us
            keymap_model=pc104
            keymap_options=terminate:ctrl_alt_bksp
            keymap_variant=

            [libinput]
            enable-tap=true
            left-handed=false
          '';
        }}

        # ---------------------------------------------------------------
        # 4. Display-manager swap. Order matters — disable competing
        #    DMs FIRST so their `[Install] Alias=display-manager.service`
        #    symlinks come down before we install sddm's, otherwise
        #    `systemctl enable sddm.service` silently leaves the old
        #    alias in place.
        # ---------------------------------------------------------------
        # 4a. What's currently wired up?
        current_dm=""
        if [ -L /etc/systemd/system/display-manager.service ]; then
          current_dm=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
        fi

        if [ "$current_dm" = "sddm" ]; then
          echo "SDDM is already the default display manager. Theme + cursor refreshed; no swap needed." >&2
        else
          # 4b. Disable known DMs. Loop over a fixed list rather than
          # parsing `systemctl list-unit-files` — explicit allowlist
          # avoids accidentally disabling something we don't recognise
          # (e.g. a custom user DM unit).
          for dm in gdm gdm3 lightdm lxdm xdm; do
            if systemctl cat "$dm.service" >/dev/null 2>&1 \
               && systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
              echo "Disabling existing display manager: $dm" >&2
              sudo systemctl disable "$dm.service" >/dev/null 2>&1 || true
            fi
          done

          # 4c. If the generic alias still points anywhere but sddm,
          # remove it so step 4d's enable can install a clean symlink.
          # A leftover alias is the most common reason swaps "fail
          # silently" — systemd treats the existing symlink as already-
          # configured and won't overwrite without --force.
          if [ -L /etc/systemd/system/display-manager.service ]; then
            tgt=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
            if [ "$tgt" != "sddm" ]; then
              sudo rm -f /etc/systemd/system/display-manager.service
            fi
          fi

          # 4d. Enable SDDM. sddm.service ships with
          # `[Install] Alias=display-manager.service`, so this also
          # creates the generic symlink.
          sudo systemctl enable sddm.service

          # 4e. Belt-and-suspenders: verify the alias landed.
          # Some distro builds of sddm.service omit the Alias line
          # (Arch's main repo used to). If so, materialise the symlink
          # ourselves from the unit's FragmentPath.
          if [ ! -L /etc/systemd/system/display-manager.service ] \
             || [ "$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)" != "sddm" ]; then
            sddm_unit=$(systemctl show -p FragmentPath sddm.service --value 2>/dev/null)
            if [ -n "$sddm_unit" ] && [ -e "$sddm_unit" ]; then
              echo "Materialising display-manager.service → $sddm_unit (sddm.service had no Alias)." >&2
              sudo rm -f /etc/systemd/system/display-manager.service
              sudo ln -sf "$sddm_unit" /etc/systemd/system/display-manager.service
            else
              echo "ERROR: sddm.service has no readable FragmentPath. Display manager alias not set." >&2
              exit 1
            fi
          fi

          # 4f. Debian's debconf-tracked default. If we don't update
          # this, a future `apt upgrade` of the previous DM can run its
          # postinst and flip the symlink back.
          if command -v apt-get >/dev/null 2>&1 && [ -d /etc/X11 ]; then
            sddm_bin=$(command -v sddm 2>/dev/null || echo /usr/bin/sddm)
            echo "$sddm_bin" | sudo tee /etc/X11/default-display-manager >/dev/null
          fi

          # 4g. Make sure we actually boot into graphical mode.
          if [ "$(sudo systemctl get-default 2>/dev/null)" != "graphical.target" ]; then
            sudo systemctl set-default graphical.target >/dev/null
          fi

          echo "" >&2
          echo "SDDM is now the default display manager (effective on next reboot)." >&2
          echo "Skipping 'systemctl restart display-manager' to avoid logging out the current session." >&2
        fi
      '';
    };
}
