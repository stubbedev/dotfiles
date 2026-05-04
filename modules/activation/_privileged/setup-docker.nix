_: {
  enableIf = { config, ... }: config.features.docker;
  args =
    { config, ... }:
    {
      promptTitle = "Installing Docker";
      promptBody = ''
        Install Docker (engine + compose) via the host's package manager,
        enable the docker.service systemd unit, and add ${config.home.username}
        to the docker group so non-root containers work without sudo.

        On NixOS, set virtualisation.docker.enable = true in the system
        config instead — this activation is gated off there.
      '';
      promptQuestion = "Install Docker?";
      actionScript = ''
        # Activation scripts run with a stripped PATH; bring the standard
        # system paths back so command -v can find dnf/apt-get/pacman.
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

        if ! command -v docker >/dev/null 2>&1; then
          if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
          elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y docker docker-compose
          elif command -v apt-get >/dev/null 2>&1; then
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' RETURN
            curl -fsSL https://get.docker.com -o "$tmp/get-docker.sh"
            sudo sh "$tmp/get-docker.sh"
          else
            echo "No supported package manager (pacman/dnf/apt-get) found." >&2
            exit 1
          fi
        fi

        # Idempotent group + membership setup. groupadd -f is a no-op if it
        # exists; the id check avoids a redundant usermod (and the resulting
        # journal log line) on every activation.
        sudo groupadd -f docker
        if ! id -nG ${config.home.username} | tr ' ' '\n' | grep -qx docker; then
          sudo usermod -aG docker ${config.home.username}
          echo "Added ${config.home.username} to the docker group; log out and back in for it to take effect."
        fi

        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl enable --now docker.service >/dev/null 2>&1 || true
        fi
      '';
      skipMessage = "Skipped. Docker won't be available until you re-run home-manager switch and accept this prompt.";
    };
}
