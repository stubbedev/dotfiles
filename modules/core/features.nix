_:
let
  workstation = [ "workstation" ];
  everywhere = [
    "workstation"
    "mobile"
  ];

  flags = {
    desktop = {
      description = "Interactive workstation UI (GUI apps, compositor support, theming). Does NOT control baseline CLI tools, the shell, tmux or the editor: they run on hosts with no display.";
      profiles = workstation;
    };
    development = {
      description = "Language toolchains beyond the CLI baseline (node, python). Project toolchains (go, rust, C/C++) come from each repo's flake dev shell, loaded by direnv.";
      profiles = workstation;
    };
    ops = {
      description = "Infrastructure tooling: hcloud with its Hetzner token, the GoDaddy credentials, and the NixOS installer ISO builder.";
      profiles = workstation;
    };
    docker = {
      description = "Docker. On NixOS this drives virtualisation.docker; elsewhere a privileged activation renders the engine's systemd units from the same locked nixpkgs docker (socket-activated, live-restore), wires the group, daemon.json and the registry:3 container.";
      profiles = workstation;
    };
    avahi = {
      description = "mDNS `*.local` resolution. On NixOS via services.avahi; elsewhere avahi-daemon + libnss-mdns from the host package manager.";
      profiles = workstation;
    };
    openssh = {
      description = "Accept inbound ssh. Elsewhere openssh-server from the host package manager; on NixOS services.openssh stays unconditional so the installer ISO keeps its remote-debug path.";
      profiles = workstation;
    };
    lysWm = {
      description = "The lys-wm compositor, its session, and login (greetd autologin).";
      profiles = workstation;
    };
    lysShell = {
      description = "The lys-shell desktop shell — bar, notifications, OSD, wallpaper, lock, portal. The default and only shell; disabling leaves no bar.";
      profiles = workstation;
    };
    theming = {
      description = "Theme packages and settings (GTK, Qt, icons, cursor, fonts, Plymouth).";
      profiles = workstation;
    };
    media = {
      description = "Image, video and audio tooling, plus the office suite.";
      profiles = workstation;
    };
    vpn = {
      description = "The GlobalProtect VPN: a NetworkManager openconnect profile provisioned from sops, signed into and toggled from lys-shell's network widget, plus a suspend/resume restore hook.";
      profiles = workstation;
    };
    srv = {
      description = "The srv local-site server; 'srv install' owns CA trust and DNS.";
      profiles = workstation;
    };
    treeman = {
      description = "treeman per-worktree DB orchestrator plus the treemand user daemon.";
      profiles = workstation;
    };
    php = {
      description = "PHP: static CLI interpreter plus FrankenPHP and composer.";
      profiles = workstation;
    };
    claudeCode = {
      description = "Claude Code CLI and its managed settings. Per-repo .mcp.json adds servers; notmuch is the only global one.";
      profiles = everywhere;
    };
    harness = {
      description = "Harness CLI (the stubbedev Crush fork) with the Z.ai provider and the shared LSP inventory.";
      profiles = workstation;
    };
    browsers = {
      description = "Web browsers (Firefox, Google Chrome) and their managed policies.";
      profiles = workstation;
    };
    slack = {
      description = "Slack desktop client.";
      profiles = workstation;
    };
  };
in
{
  flake.modules.homeManager.features =
    { config, lib, ... }:
    {
      options.features = lib.mapAttrs (
        _: flag:
        lib.mkOption {
          type = lib.types.bool;
          default = builtins.elem config.host.profile flag.profiles;
          defaultText = lib.literalMD "on for the ${lib.concatStringsSep " and " flag.profiles} profile";
          inherit (flag) description;
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
        let
          inherit (config.host) primaryUser;
        in
        if config.home-manager.users ? ${primaryUser} then
          config.home-manager.users.${primaryUser}.features
        else
          lib.mapAttrs (_: _: false) flags;
    };
}
