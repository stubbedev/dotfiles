{ self, ... }:
{
  # Login on non-NixOS hosts (Ubuntu, ...): greetd with autologin straight into
  # Hyprland. Replaces the old SDDM + kwin_wayland greeter (setup-sddm.nix).
  #
  # Why the swap: SDDM ran kwin_wayland as a full Wayland-compositor greeter
  # that holds DRM master, and hands the session off before kwin finishes
  # tearing down the GPU. With an external display lit via the Thunderbolt dock
  # that teardown lags ~575ms, so Hyprland lost the DRM-master handoff race
  # (`seatd: drm master: Device or resource busy`) and black-screened. greetd
  # autologin runs Hyprland directly with nothing holding DRM master ahead of
  # it, so the race cannot happen. Access gate: wayle-lock at Hyprland start
  # (src/hypr/hyprland.lua) — the session boots to a locked screen.
  #
  # Kept in sync with the NixOS path (modules/nixos/greetd.nix): same launcher
  # (src/greetd/hyprland-session.sh), same autologin + agreety-fallback shape.
  enableIf = { config, ... }: config.features.hyprland;
  args =
    { config, homeLib, ... }:
    let
      # greetd execs this at boot. Installed to /etc — NOT referenced as a nix
      # store path — so `nix-collect-garbage` can never remove the file login
      # depends on. It resolves start-hyprland at runtime from the user's
      # (GC-rooted) HM profile.
      launcher = "/etc/greetd/hyprland-session.sh";
      configToml = ''
        # Managed by stubbedev dotfiles —
        # modules/activation/_privileged/setup-greetd.nix
        [terminal]
        vt = 1

        # Autologin: no interactive greeter at boot, straight into Hyprland.
        [initial_session]
        command = "${launcher}"
        user = "${config.home.username}"

        # Fallback after an explicit logout: agreety text prompt (not a
        # compositor, never takes DRM master). Runs as the greetd greeter user.
        [default_session]
        command = "agreety --cmd ${launcher}"
        user = "greeter"
      '';
    in
    homeLib.mkInstallPrompt {
      subject = "greetd (autologin login manager, replaces SDDM)";
      body = ''
        Install greetd (ships the agreety fallback greeter) via the host
        package manager, drop the shared Hyprland session launcher into
        /etc/greetd, write /etc/greetd/config.toml (autologin into Hyprland,
        agreety on logout), and make greetd the system display manager in place
        of SDDM.

        The display-manager swap disables any enabled DM (sddm/gdm/lightdm/...),
        repoints /etc/systemd/system/display-manager.service at greetd.service,
        and sets graphical.target as default. It does NOT restart the display
        manager — takes effect on next reboot, so the current session survives.

        Recovery if autologin ever fails to render: switch to a text console
        (Ctrl+Alt+F3) and log in there to fix or roll back.
      '';
      actionScript = ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        # 1. Install greetd (agreety ships with it).
        ${homeLib.installHostPackage {
          detect = "greetd";
          apt = [ "greetd" ];
          dnf = [ "greetd" ];
          pacman = [ "greetd" ];
        }}

        # 2. Ensure the unprivileged `greeter` user greetd drops to for the
        #    agreety fallback exists (Debian's package usually creates it;
        #    idempotent here for other distros / partial installs).
        if ! getent passwd greeter >/dev/null 2>&1; then
          sudo useradd --system --create-home --home-dir /var/lib/greetd \
            --shell /usr/sbin/nologin --user-group \
            --groups video,input greeter 2>/dev/null || true
        fi

        # 3. Shared session launcher (also used by NixOS). 0755, in /etc.
        ${homeLib.installSystemFile {
          target = launcher;
          mode = "0755";
          content = builtins.readFile (self + "/src/greetd/hyprland-session.sh");
        }}

        # 4. greetd config.
        sudo install -d -m 0755 /etc/greetd
        ${homeLib.installSystemFile {
          target = "/etc/greetd/config.toml";
          content = configToml;
        }}

        # 5. Display-manager swap. Disable competing DMs FIRST so their
        #    `[Install] Alias=display-manager.service` symlinks come down.
        current_dm=""
        if [ -L /etc/systemd/system/display-manager.service ]; then
          current_dm=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
        fi

        if [ "$current_dm" = "greetd" ]; then
          echo "greetd is already the default display manager; config refreshed." >&2
        else
          for dm in sddm gdm gdm3 lightdm lxdm xdm; do
            if systemctl cat "$dm.service" >/dev/null 2>&1 \
               && systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
              echo "Disabling existing display manager: $dm" >&2
              sudo systemctl disable "$dm.service" >/dev/null 2>&1 || true
            fi
          done

          if [ -L /etc/systemd/system/display-manager.service ]; then
            tgt=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
            if [ "$tgt" != "greetd" ]; then
              sudo rm -f /etc/systemd/system/display-manager.service
            fi
          fi

          sudo systemctl enable greetd.service

          # Materialise the alias ourselves if greetd.service omits it.
          if [ ! -L /etc/systemd/system/display-manager.service ] \
             || [ "$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)" != "greetd" ]; then
            greetd_unit=$(systemctl show -p FragmentPath greetd.service --value 2>/dev/null)
            if [ -n "$greetd_unit" ] && [ -e "$greetd_unit" ]; then
              echo "Materialising display-manager.service → $greetd_unit." >&2
              sudo rm -f /etc/systemd/system/display-manager.service
              sudo ln -sf "$greetd_unit" /etc/systemd/system/display-manager.service
            else
              echo "ERROR: greetd.service has no readable FragmentPath. Display manager alias not set." >&2
              exit 1
            fi
          fi

          if command -v apt-get >/dev/null 2>&1 && [ -d /etc/X11 ]; then
            greetd_bin=$(command -v greetd 2>/dev/null || echo /usr/bin/greetd)
            echo "$greetd_bin" | sudo tee /etc/X11/default-display-manager >/dev/null
          fi

          if [ "$(sudo systemctl get-default 2>/dev/null)" != "graphical.target" ]; then
            sudo systemctl set-default graphical.target >/dev/null
          fi

          echo "" >&2
          echo "greetd is now the default display manager (effective on next reboot)." >&2
          echo "Not restarting the display manager, to avoid killing the current session." >&2
        fi
      '';
    };
}
