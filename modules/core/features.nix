_:
let
  flags = {
    desktop = "Interactive workstation UI (GUI apps, compositor support, theming). Does NOT control baseline CLI tools.";
    development = "Language toolchains beyond the CLI baseline (node, python). Project toolchains (go, rust, C/C++) come from each repo's devenv.";
    docker = "Docker. On NixOS this drives virtualisation.docker; elsewhere a privileged activation renders the engine's systemd units from the same locked nixpkgs docker (socket-activated, live-restore), wires the group, daemon.json and the registry:3 container.";
    avahi = "mDNS `*.local` resolution. On NixOS via services.avahi; elsewhere avahi-daemon + libnss-mdns from the host package manager.";
    openssh = "Accept inbound ssh. On NixOS via services.openssh; elsewhere openssh-server from the host package manager.";
    hyprland = "The Hyprland compositor, its session, and login (greetd autologin).";
    wayle = "The wayle desktop shell — bar, notifications, OSD, wallpaper, lock, portal. The default and only shell; disabling leaves no bar.";
    theming = "Theme packages and settings (GTK, Qt, icons, cursor, fonts, Plymouth).";
    media = "Image, video and audio tooling, plus the office suite.";
    vpn = "The GlobalProtect VPN: a NetworkManager openconnect profile provisioned from sops, signed into and toggled from wayle's network widget, plus a suspend/resume restore hook.";
    srv = "The srv local-site server; 'srv install' owns CA trust and DNS.";
    treeman = "treeman per-worktree DB orchestrator plus the treemand user daemon.";
    php = "PHP: static CLI interpreter plus FrankenPHP and composer.";
    claudeCode = "Claude Code CLI and its managed settings. Per-repo .mcp.json adds servers; notmuch is the only global one.";
    harness = "Harness CLI (the stubbedev Crush fork) with the Z.ai provider and the shared LSP inventory.";
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

  # The fallback matters: the installer ISO imports every NixOS aspect but
  # declares no home-manager user, so there is nothing to read.
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
