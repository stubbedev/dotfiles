{ config, inputs, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.nix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Without this, system packages fall back to a vanilla nixpkgs eval and
      # miss every override. Read from the flake level, not `pkgs.stubbe`:
      # `pkgs` is built FROM these values, so that is infinite recursion.
      nixpkgs = {
        config = flakeConfig.stubbe.lib.nixpkgsConfig;
        overlays = builtins.attrValues flakeConfig.flake.overlays;
      };

      # binfmt also adds these to nix.settings.extra-platforms, which is what
      # makes the daemon build for them locally instead of failing to find a
      # builder.
      boot.binfmt.emulatedSystems = config.host.emulatedSystems;

      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          # `<nixpkgs>` resolves to the flake's pinned tree.
          nix-path = [ "nixpkgs=${inputs.nixpkgs}" ];

          # nix asks the substituter before building, so our self-hosted cache
          # 404s until the push seconds later. The default 3600s negative TTL
          # would then hide the pushed path for an hour.
          narinfo-cache-negative-ttl = 0;

          auto-optimise-store = true;

          # The default `@users` lets any local user trigger store writes.
          allowed-users = [ "@wheel" ];
          trusted-users = [
            "root"
            "@wheel"
          ];
        }
        # The substituters, their keys and the download tuning are shared with
        # the phone (modules/core/lib/nix-settings.nix).
        // pkgs.stubbe.cache.settings;

        # Optional form, so an early-boot eval before the secret exists is fine.
        extraOptions = ''
          !include ${config.sops.templates."nix-access-tokens.conf".path}
        '';

        daemonCPUSchedPolicy = "idle";
        daemonIOSchedClass = "idle";

        # Old generation symlinks are GC roots, so they must be pruned BEFORE
        # collecting or there is nothing to free. `--delete-older-than` is
        # time-based and lets the count drift with switch frequency.
        gc = {
          automatic = true;
          dates = "weekly";
          options = "";
        };

        optimise = {
          automatic = true;
          dates = [ "weekly" ];
        };

        # A stale `nix-channel --update` could drift the system off flake.lock.
        channel.enable = false;
      };

      # Idle scheduling makes the weekly timers yield to anything interactive.
      systemd.services = {
        nix-gc.serviceConfig = {
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
        };
        nix-optimise.serviceConfig = {
          IOSchedulingClass = "idle";
          CPUSchedulingPolicy = "idle";
        };
      };

      system.activationScripts.pruneSystemGenerations.text = ''
        ${lib.getExe' config.nix.package "nix-env"} --profile /nix/var/nix/profiles/system --delete-generations +2
      '';

      # Rendered into /run, not the store: `nix.settings.access-tokens` would
      # put the token in the world-readable nix.conf. Owned by primaryUser
      # because `nix flake update` runs unprivileged even on NixOS.
      sops = {
        secrets.github-token = pkgs.stubbe.secret { name = "github-token"; };
        templates."nix-access-tokens.conf" = {
          content = "access-tokens = github.com=${config.sops.placeholder.github-token}";
          owner = config.host.primaryUser;
          mode = "0400";
        };
      };
    };

  flake.modules.homeManager.nix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      onAndroid = config.host.platform == "android";
      accessTokensFile = "${config.home.homeDirectory}/.config/nix/access-tokens.conf";

      xiloCache = pkgs.stubbe.cache.xilo;

      # Hosts this machine builds for: the android configurations whose system
      # it emulates. Derived, so a second phone needs nothing but its system in
      # `host.emulatedSystems`.
      emulatedAndroidAttrs =
        let
          hosts = flakeConfig.configurations.nixOnDroid;
          emulated = builtins.filter (name: builtins.elem hosts.${name}.system config.host.emulatedSystems) (
            builtins.attrNames hosts
          );
        in
        map (name: "nixOnDroidConfigurations.${name}.activationPackage") emulated;

      # phix appends the generation it just built to every post-switch hook's
      # arguments, so the attribute is the first argument and the rest is
      # ignored.
      xiloPushClosure = pkgs.stubbe.bashApp {
        name = "xilo-push-closure";
        runtimeInputs = [
          pkgs.nix
          pkgs.xilo
        ];
        text = ''
          attr="$1"
          storePath=$(nix build "$PHIX_FLAKE#$attr" --no-link --print-out-paths --no-write-lock-file)
          xilo push --quiet ${xiloCache.cache} "$storePath"
        '';
      };

      # The machine's own closure, then every closure it builds for a host that
      # cannot build its own: `phix switch` and `phix upgrade` run both, so the
      # phone substitutes its closure instead of compiling it.
      cacheHooks = [
        {
          description = "Pushing the closure to ${xiloCache.url}";
          exec = lib.getExe' pkgs.xilo "xilo";
          args = [
            "push"
            "--quiet"
            xiloCache.cache
          ];
          env.XILO_URL = xiloCache.url;
          secretEnv.XILO_TOKEN = "xilo-token";
        }
      ]
      ++ map (attr: {
        description = "Pushing ${attr} to ${xiloCache.url}";
        exec = lib.getExe xiloPushClosure;
        args = [ attr ];
        env.XILO_URL = xiloCache.url;
        secretEnv.XILO_TOKEN = "xilo-token";
      }) emulatedAndroidAttrs;
    in
    {
      home.packages = lib.mkIf config.features.development [
        pkgs.xilo
        pkgs.shell-lsp
        pkgs.nixdoc
      ];

      stubbe.zshCompletions._xilo = lib.mkIf config.features.development "${lib.getExe' pkgs.xilo "xilo"} completion zsh";

      programs.phix.postSwitch = lib.mkIf config.features.development cacheHooks;

      # Generations only: on NixOS the system nix.gc above sweeps the store
      # weekly, and on Android `nix-on-droid trim` owns it.
      services.home-manager.autoExpire = {
        enable = !onAndroid;
        timestamp = "-30 days";
        frequency = "weekly";
      };

      # Anonymous api.github.com allows 60 requests/hr, and `nix flake update`
      # resolves every input HEAD against it, so one run exhausts the budget and
      # silently falls back to stale cached revs.
      #
      # Pulled in by reference, not through `nix.settings.access-tokens`: that
      # would put the token in the world-readable store copy of nix.conf.
      # `!include` is the optional form, so a nix call before the first sops
      # render -- or after a reboot wipes $XDG_RUNTIME_DIR, until
      # sops-nix.service re-renders -- is fine rather than a hard error.
      #
      # On NixOS the system nix.conf carries the same line (see the nixos
      # module above) and generating a user nix.conf here would shadow it.
      sops = lib.mkIf onAndroid {
        templates."nix-access-tokens.conf" = {
          content = "access-tokens = github.com=${config.sops.placeholder.github-token}";
          path = accessTokensFile;
        };
      };

      # The phone has no daemon and no system nix.conf of ours: nix-on-droid
      # writes the stock cache.nixos.org/nix-on-droid.cachix.org pair, so
      # everything this repo builds itself is compiled on the device. The user
      # nix.conf is the only place aarch64 can be pointed at xilos.dev.
      nix.settings = lib.mkIf onAndroid pkgs.stubbe.cache.settings;

      nix.extraOptions = lib.mkIf onAndroid ''
        !include ${accessTokensFile}
      '';
    };
}
