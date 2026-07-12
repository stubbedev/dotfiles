{
  description = "stubbedev dotfiles: home-manager (non-NixOS) + NixOS configurations + installer ISO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Pinned to KeeTraxx PR #221 (https://github.com/nix-community/nixGL/pull/221)
    # Drops `kernel = null` override removed from nixpkgs nvidia-x11/generic.nix
    # and fixes version regex for NVIDIA Open Kernel Module 595.71.05+
    # Switch back to github:nix-community/nixGL once #221 is merged
    nixgl = {
      url = "github:KeeTraxx/nixGL/fix-nvidia-kernel-param";
      # We import nixgl via a path with `pkgs = final` (modules/overlays.nix),
      # so nixgl's flake outputs (and its own nixpkgs) are never used — follow
      # ours to drop a redundant nixpkgs from the lock.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Use official Hyprland flake for better plugin compatibility.
    # Use tag ref explicitly (refs/tags/…) so Nix does not look for a
    # non-existent branch named the version string when updating the flake input.
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.55.4&submodules=1";

    hyprland-guiutils = {
      url = "github:hyprwm/hyprland-guiutils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hy3 = {
      # hl0.55.0 targets hyprland 0.55.1; compatible with our v0.55.4.
      # Follows our hyprland input so it builds against the same headers.
      url = "github:outfoxxed/hy3?ref=refs/tags/hl0.55.0";
      inputs.hyprland.follows = "hyprland";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Don't follow nixpkgs — fenix cache (nix-community.cachix.org) is built
    # against nixpkgs-unstable; following our nixpkgs causes cache misses.
    fenix.url = "github:nix-community/fenix";
    srv.url = "github:stubbedev/srv";
    treeman = {
      url = "github:stubbedev/treeman";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # xilo: client for our self-hosted Nix binary cache (nix.stubbe.dev).
    # bin/hm pushes each switch's closure here so other machines substitute
    # what this one compiled. Pinned to the tag the SERVER runs (v1.0.0): the
    # cache-config API is versioned, so a client ahead of the server 404s.
    # Bump in lockstep with the server (see project_xilo_cache_server memory).
    xilo = {
      url = "github:stubbedev/xilo/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Go-rewritten work MCP servers, consumed as flake packages (buildGoModule)
    # so they spawn as offline store-path binaries instead of `npx …@latest`.
    # Wired into lib/mcp-servers.nix via setup-claude-code.nix. atlassian-mcp is
    # not here yet — still the pinned npx wrapper until its Go rewrite lands.
    jenkins-mcp = {
      url = "github:stubbedev/jenkins-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sentry-mcp = {
      url = "github:stubbedev/sentry-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atlassian-mcp = {
      url = "github:stubbedev/atlassian-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Readonly DB MCP server (Rust). One unified server for MySQL + MongoDB
    # (and more); replaces the separate mysql-mcp / mongodb-mcp. Joins the
    # `proxied` set in lib/mcp-servers.nix. Like pty-mcp/wayle, it ships its
    # own binary cache (nix.stubbe.dev/default) built against its OWN
    # flake.lock nixpkgs — don't follow ours or every store path misses the
    # cache and rustc builds locally.
    ds-mcp.url = "github:stubbedev/ds-mcp";
    html-to-md = {
      url = "github:stubbedev/html-to-md";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-mcp = {
      url = "github:stubbedev/nix-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cship = {
      url = "github:stephenleo/cship";
      flake = false;
    };
    # proxy-mcp (stubbedev): aggregating MCP proxy with a real readiness gate.
    # Backs the chrome-devtools `proxied` entry in lib/mcp-servers.nix,
    # replacing TBXark/mcp-proxy. Ships its own flake, so it is consumed as a
    # package directly (no buildGoModule overlay). Its Type=notify
    # sd_notify(READY=1) gate fires only after the wrapped upstream's MCP route
    # is registered, so mcp-services.nix drops the hand-rolled ExecStartPost
    # TCP-probe and gates the backend on real readiness.
    proxy-mcp = {
      url = "github:stubbedev/proxy-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # pty-mcp (stubbedev): real-terminal MCP server — one-shot `run` in the
    # user's shell plus persistent PTY sessions, sudo via a native askpass
    # dialog. Rust. Joins the `proxied` set in lib/mcp-servers.nix (shared
    # proxy port, on-demand). CI pushes its closure to nix.stubbe.dev/default
    # built against its OWN flake.lock nixpkgs — don't follow ours or every
    # store path misses the cache and rustc builds locally (same reason as
    # wayle/fenix above).
    pty-mcp.url = "github:stubbedev/pty-mcp";
    # Wayland desktop shell (Rust/GTK4): bar + notifications + OSD + wallpaper.
    # Ships its own flake; we consume overlays.default (modules/overlays.nix).
    wayle = {
      # ?submodules=1: wayle-cava vendors cava's C sources as a git submodule
      # (crates/wayle-cava/cava); the github fetcher skips submodules by default,
      # which leaves cava/src/*.c missing and breaks the build.
      url = "git+https://github.com/stubbedev/wayle.git?ref=master&submodules=1";
      # Don't follow nixpkgs — wayle's binary cache (nix.stubbe.dev/wayle) is
      # built by CI against wayle's *own* flake.lock nixpkgs. Following ours
      # rebases every derivation onto a different nixpkgs, so no store-path hash
      # matches the cache and everything rebuilds from source. Same reason as
      # fenix above. Cost: a second nixpkgs in the closure — worth it for a
      # working cache.
    };
    # Zsh plugins consumed as pinned sources (no runtime git clones).
    # zcompiled into the stubbe-zsh-plugins derivation by
    # modules/home/zsh/_packages.nix; refreshed via `nix flake update`,
    # which replaced the daily zsh-plugin-update timer.
    zsh-vim-mode = {
      url = "github:softmoth/zsh-vim-mode";
      flake = false;
    };
    zsh-fzf-artisan = {
      url = "github:stubbedev/zsh-fzf-artisan";
      flake = false;
    };
    zsh-fzf-npm-run = {
      url = "github:stubbedev/zsh-fzf-npm-run";
      flake = false;
    };
    # Zsh syntax highlighting via a shared Rust daemon (syntect-based).
    # Replaces the fast-syntax-highlighting zsh plugin; consumed as
    # pkgs.zsh-patina via modules/overlays.nix, activated in src/zsh/settings.
    zsh-patina = {
      url = "github:michel-kraemer/zsh-patina";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # PHP language server (Rust). Ships its own flake; we consume
    # packages.default via the phpantom_lsp overlay (modules/overlays.nix).
    phpantom_lsp = {
      url = "github:PHPantom-dev/phpantom_lsp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Used by the installer ISO build for partitioning declaration.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets management. Encrypted secrets live under secrets/, keyed to
    # per-machine age recipients in .sops.yaml. Decrypted at HM activation.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Signed bootloader for UEFI Secure Boot. Activated only when
    # host.secureBoot = true; see modules/nixos/lanzaboote.nix.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative bind-mounts + tmpfs root for stateless systems.
    # Activated only when host.impermanent = true; see
    # modules/nixos/impermanence.nix.
    impermanence = {
      url = "github:nix-community/impermanence";
      # Pure NixOS module, no build artifacts — follow ours to drop a
      # redundant nixpkgs from the lock.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Wraps Neovim with a lua config dir + nixpkgs-supplied LSPs/tools.
    # Lua tree lives at src/nvim/, symlinked into ~/.config/nvim by
    # modules/activation/_non-privileged/setup-nvim.nix; lazy.nvim handles
    # plugin downloads from GitHub at runtime.
    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
