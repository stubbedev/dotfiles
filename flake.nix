{
  description = "stubbedev dotfiles: home-manager (non-NixOS) + NixOS configurations + installer ISO";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nix-community/nixGL#221 (NVIDIA kernel-param regex for 595.71.05+) is
    # still open upstream, but it only matters for nixgl's NVIDIA wrapper —
    # which this config never uses: NVIDIA hosts dispatch via the host's glvnd
    # (modules/core/pkgs/gl.nix), and only nixGLIntel is consumed, identical in
    # both trees.
    nixgl = {
      url = "github:nix-community/nixgl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Inputs that ship a binary cache do NOT follow our nixpkgs: their caches are
    # built against their own locked nixpkgs, and rebasing every derivation onto
    # ours means no store-path hash matches and everything builds from source.
    srv.url = "github:stubbedev/srv";
    treeman = {
      url = "github:stubbedev/treeman";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned to the tag the SERVER runs: the cache-config API is versioned, so a
    # client ahead of the server 404s.
    xilo = {
      url = "github:stubbedev/xilo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    adaptive-power-manager = {
      url = "github:stubbedev/adaptive-power-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The Crush fork: config-driven theming, git header, thinking toggle and
    # prompt height, so nothing has to be patched into the Go source here.
    harness = {
      url = "github:stubbedev/harness";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Composer, natively: a Go port of Composer installed as `composer`
    # (modules/php.nix). flake.lock pins it; `nix flake update maestro` moves it.
    maestro = {
      url = "github:stubbedev/maestro";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    html-to-md = {
      url = "github:stubbedev/html-to-md";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cship = {
      url = "github:stephenleo/cship";
      flake = false;
    };
    claude-code = {
      # Tracks npm latest within ~1h of release; nixpkgs' claude-code lags.
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    notmuch-mcp = {
      url = "github:stubbedev/notmuch-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wayle = {
      # ?submodules=1: the github fetcher skips submodules, leaving the vendored
      # cava C sources missing.
      url = "git+https://github.com/stubbedev/wayle.git?ref=master&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    phpantom_lsp = {
      url = "github:PHPantom-dev/phpantom_lsp/0.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    libembroidery-src = {
      url = "github:Embroidermodder/libembroidery";
      flake = false;
    };
    # Unversioned PECL URL: always resolves to the newest mongodb release, so
    # the version is whatever `nix flake update mongodb-php-src` last pulled
    # rather than a hand-written hash. The PECL release tarball bundles
    # libmongoc/libmongocrypt, so it needs no submodule fetch.
    mongodb-php-src = {
      url = "https://pecl.php.net/get/mongodb";
      type = "tarball";
      flake = false;
    };
    tridactyl-theme-src = {
      url = "github:devnullvoid/tridactyl";
      flake = false;
    };
    # Prebuilt release binary. The version lives in this URL and is pinned by
    # flake.lock like every other input; the overlay consumes the tree
    # directly. Bump by hand: update the tag here, run `nix flake lock`.
    yayamlls = {
      url = "https://github.com/home-operations/yayamlls/releases/download/0.3.2/yayamlls_0.3.2_linux_amd64.tar.gz";
      type = "tarball";
      flake = false;
    };

    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
