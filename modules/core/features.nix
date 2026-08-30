# The flag TABLE below is the single source of truth: the home-manager options
# are generated from it, and so is the NixOS-side mirror at the bottom — which
# is what lets a NixOS aspect ask "did this host enable features.docker?"
# without every module repeating `config.home-manager.users.<user>.features or { }`.
_:
let
  flags = {
    desktop = "Interactive workstation UI (GUI apps, compositor support, theming). Does NOT control baseline CLI tools.";
    development = "Language toolchains beyond the CLI baseline (node, go, rust via fenix).";
    docker = "Docker. On NixOS this drives virtualisation.docker; elsewhere a privileged activation installs it via the host package manager and adds the user to the docker group.";
    avahi = "mDNS `*.local` resolution. On NixOS via services.avahi; elsewhere avahi-daemon + libnss-mdns from the host package manager.";
    openssh = "Accept inbound ssh. On NixOS via services.openssh; elsewhere openssh-server from the host package manager.";
    hyprland = "The Hyprland compositor, its session, and login (greetd autologin).";
    wayle = "The wayle desktop shell — bar, notifications, OSD, wallpaper, lock, portal. The default and only shell; disabling leaves no bar.";
    theming = "Theme packages and settings (GTK, Qt, icons, cursor, fonts, Plymouth).";
    media = "Image, video and audio tooling, plus the office suite.";
    vpn = "The openconnect VPN: systemd tunnel units, their secrets, and the systemctl polkit rule.";
    rust = "The rust toolchain (fenix stable).";
    srv = "The srv local-site server and the mkcert CA trust that goes with it.";
    treeman = "treeman per-worktree DB orchestrator plus the treemand user daemon.";
    php = "PHP: one build serving the CLI, php-fpm and FrankenPHP.";
    k8s = "Kubernetes tools (kubectl, minikube).";
    claudeCode = "Claude Code CLI, its managed settings, and the MCP inventory.";
    codex = "Codex CLI, wired to the same MCP inventory.";
    opencode = "opencode CLI.";
    browsers = "Web browsers (Firefox, Google Chrome) and their managed policies.";
    slack = "Slack desktop client.";
  };
in
{
  flake.modules.homeManager.features =
    { lib, ... }:
    {
      options.features = lib.mapAttrs (
        _: description:
        lib.mkOption {
          type = lib.types.bool;
          default = true;
          inherit description;
        }
      ) flags;
    };

  # The NixOS mirror. A NixOS aspect gates on `config.stubbe.userFeatures.<x>`,
  # resolved ONCE here from the primary user's home-manager config.
  # The fallback matters: the installer ISO imports every NixOS aspect but
  # declares no home-manager user, so there is nothing to read. Everything off
  # is the right answer there — the ISO wants a bootable installer, not a
  # workstation.
  flake.modules.nixos.features =
    { config, lib, ... }:
    {
      options.stubbe.userFeatures = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        internal = true;
        description = "The primary user's `features.*` flags, for NixOS aspects to gate on.";
      };

      config.stubbe.userFeatures =
        config.home-manager.users.${config.host.primaryUser}.features or (lib.mapAttrs (_: _: false) flags);
    };
}
