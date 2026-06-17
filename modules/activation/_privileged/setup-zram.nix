_: {
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "zram compressed swap";
      body = ''
        Install systemd-zram-generator, write a managed
        /etc/systemd/zram-generator.conf (zstd, size = RAM/2), and bring up
        the systemd-zram-setup@zram0 service so a compressed RAM swap device
        absorbs memory pressure before the disk swapfile fills.

        Without it, earlyoom fires under load and SIGTERMs Chrome/Electron
        renderers (oom_score_adj +300) across every chromium-family app
        ("Aw, Snap!", blank Slack). zram gives ~3x effective headroom so the
        OOM threshold is rarely hit.

        On NixOS, zramSwap (modules/nixos/zram.nix) handles this; this
        activation is gated off there.
      '';
      # Reinstall if the package is removed: the generator binary appearing
      # / disappearing flips the lock so this re-runs.
      stateInputs = [ "/usr/lib/systemd/system-generators/zram-generator" ];
      preCheck = homeLib.requireCommand "systemctl";
      actionScript = ''
        # Activations run with a stripped PATH; restore it so command -v
        # finds apt-get / dnf / pacman under /usr/sbin etc.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        # systemd-zram-generator ships only a systemd generator (no PATH
        # binary), so installHostPackage's `command -v` detection can't see
        # it — gate on the generator file instead. Package name differs:
        # Debian/Ubuntu call it systemd-zram-generator, Fedora/Arch zram-generator.
        if [ ! -e /usr/lib/systemd/system-generators/zram-generator ] \
           && [ ! -e /lib/systemd/system-generators/zram-generator ]; then
          if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y --no-install-recommends systemd-zram-generator
          elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y --setopt=install_weak_deps=False zram-generator
          elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm zram-generator
          else
            echo "No supported package manager (apt-get/dnf/pacman) found." >&2
            exit 1
          fi
        fi

        # Mirror modules/nixos/zram.nix: zstd, 50% of RAM.
        ${homeLib.installSystemFile {
          target = "/etc/systemd/zram-generator.conf";
          content = ''
            # managed-by: home-manager zram
            [zram0]
            zram-size = ram / 2
            compression-algorithm = zstd
          '';
        }}

        # daemon-reload re-runs the generator against the new conf (creating
        # the systemd-zram-setup@zram0 instance); restart applies it live so
        # the device comes up without a reboot.
        sudo systemctl daemon-reload
        sudo systemctl restart systemd-zram-setup@zram0.service
      '';
    };
}
