_: {
  # Feature-flag contract:
  #
  #   features.desktop      Interactive workstation: GUI + the tools needed
  #                         to drive one (rofi, alacritty, mail TUI, theming,
  #                         clipboard, …). Baseline CLI tools (git, tmux,
  #                         jq, ripgrep) are NOT gated on this — they ship
  #                         unconditionally via modules/packages/cli/core.nix.
  #
  #   features.development  Extra language toolchains beyond the baseline
  #                         (nodejs/bun/pnpm, go, neovide, jetbrains-toolbox,
  #                         the nixd/nh/nil tooling pack, direnv).
  #                         Independent of `desktop`: a remote build box can
  #                         have development=true, desktop=false.
  #
  # Other flags below are toggles for individual subsystems (docker, hyprland,
  # niri, k8s, php, slack, …). All default true on stubbe's machines; flip
  # them off per-host where appropriate.
  flake.modules.homeManager.features =
    { lib, ... }:
    {
      options.features = {
        desktop = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable interactive workstation UI (GUI apps, compositor support, theming). Does NOT control baseline CLI tools.";
        };
        development = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable extra language toolchains beyond the CLI baseline (node, go, rust via fenix, jetbrains-toolbox).";
        };
        docker = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install Docker via the host package manager and add the user to the docker group. On NixOS, set virtualisation.docker.enable instead.";
        };
        avahi = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install avahi-daemon + libnss-mdns via the host package manager so `*.local` mDNS resolution works. On NixOS, the system module handles this.";
        };
        openssh = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install openssh-server via the host package manager and enable sshd so this machine accepts inbound ssh. On NixOS, services.openssh handles this.";
        };
        hyprland = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Hyprland-specific packages and configuration.";
        };
        niri = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Niri-specific packages and configuration.";
        };
        theming = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable theme packages and settings.";
        };
        media = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable media-related packages and config.";
        };
        vpn = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable VPN scripts and configuration.";
        };
        opencode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable opencode package and config.";
        };
        rust = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable rust toolchain installation";
        };
        srv = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable srv site management tool.";
        };
        php = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable php installation.";
        };
        k8s = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Kubernetes tools (kubectl, minikube).";
        };
        claudeCode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable claude-code CLI from nixpkgs unstable.";
        };
        browsers = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable web browsers (Firefox, Google Chrome).";
        };
        slack = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Slack desktop client.";
        };
      };
    };
}
