_: {
  enableIf = { config, ... }: config.features.openssh;
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "OpenSSH server";
      body = ''
        Install openssh-server via the host's package manager, drop a
        managed /etc/ssh/sshd_config.d/10-stubbedev.conf that disables
        password and root logins (matching the NixOS host), open the
        host firewall for ssh (ufw/firewalld if present), and enable
        the sshd unit.

        On NixOS, services.openssh + networking.firewall handle this;
        this activation is gated off there.
      '';
      actionScript = ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        ${homeLib.installHostPackage {
          detect = "sshd";
          apt = [ "openssh-server" ];
          dnf = [ "openssh-server" ];
          pacman = [ "openssh" ];
        }}

        # Drop a config snippet in /etc/ssh/sshd_config.d/. Modern
        # openssh on Debian/Ubuntu/Fedora/Arch all ship a main
        # sshd_config that begins with `Include /etc/ssh/sshd_config.d/
        # *.conf`, and the first occurrence of a directive wins, so a
        # snippet placed there overrides distro defaults further down.
        sudo install -d -m 0755 /etc/ssh/sshd_config.d
        ${homeLib.installSystemFile {
          target = "/etc/ssh/sshd_config.d/10-stubbedev.conf";
          content = ''
            # Managed by stubbedev dotfiles —
            # modules/activation/_privileged/setup-openssh.nix
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
          '';
        }}

        # Unit name differs across distros: Debian/Ubuntu ships
        # ssh.service, Fedora/Arch ship sshd.service. Pick whichever
        # exists, then restart so the new sshd_config.d snippet takes
        # effect (a fresh apt-get install auto-starts pre-snippet).
        if command -v systemctl >/dev/null 2>&1; then
          if systemctl cat sshd.service >/dev/null 2>&1; then
            svc=sshd.service
          elif systemctl cat ssh.service >/dev/null 2>&1; then
            svc=ssh.service
          else
            svc=""
          fi
          if [ -n "$svc" ]; then
            sudo systemctl enable "$svc" >/dev/null 2>&1 || true
            sudo systemctl restart "$svc" >/dev/null 2>&1 || true
          fi
        fi

        # Open the host firewall for ssh. Idempotent on both tools.
        # Skipped if no recognised firewall daemon is installed (Arch's
        # default state, also Ubuntu when ufw isn't installed).
        if command -v ufw >/dev/null 2>&1; then
          sudo ufw allow ssh >/dev/null 2>&1 || true
        fi
        if command -v firewall-cmd >/dev/null 2>&1 \
           && sudo firewall-cmd --state >/dev/null 2>&1; then
          sudo firewall-cmd --permanent --add-service=ssh >/dev/null
          sudo firewall-cmd --reload >/dev/null
        fi
      '';
    };
}
