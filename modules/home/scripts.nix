{ self, ... }:
{
  flake.modules.homeManager.scripts =
    {
      config,
      lib,
      pkgs,
      homeLib,
      constants,
      ...
    }:
    let
      # Standalone scripts that aren't tied to a specific app's config dir.
      # Built as Nix bins so they live under config.home.profileDirectory/bin
      # (i.e. ~/.nix-profile/bin or /etc/profiles/per-user/$USER/bin) on PATH.
      # Other modules reference paths via `${scripts.<name>}/bin/<name>` —
      # systemd ExecStart, polkit-allowed targets, etc.
      #
      # Naming convention: <namespace>-<action>.
      #   mail-*    aerc/email helpers
      #   monitor-* display brightness / monitor controls
      #   tmux-*    tmux launcher wrappers
      #   fzf-*     fzf-driven pickers (return strings; tmux-pick-* wrap them)

      flakeDir = "${config.home.homeDirectory}/.stubbe";

      # Auto-discover everything under bin/ — name == filename. Excluded:
      #   stb-install        pre-Nix bootstrap; runs from the checkout
      #   stb-install-nixos  ISO-only; iso.nix imports it via readFile
      #   hm, nixos-iso      templated separately below (need @KEY@ vars)
      autoBinExcluded = [
        "stb-install"
        "hm"
        "nixos-iso"
      ];
      binNames = lib.attrNames (
        lib.filterAttrs (name: type: type == "regular" && !(builtins.elem name autoBinExcluded)) (
          builtins.readDir (self + "/bin")
        )
      );
      binScripts = lib.genAttrs binNames (
        name:
        homeLib.mkScriptBin {
          inherit name;
          source = "bin/${name}";
        }
      );

      # Scripts under src/ — the bin name differs from the source filename
      # (or the source ends with .sh / lives under <app>/scripts/), so we
      # list them explicitly. mapAttrs forwards the attribute key as the
      # bin name; only the right-hand side varies.
      srcScripts = lib.mapAttrs (name: cfg: homeLib.mkScriptBin (cfg // { inherit name; })) {
        mail-open = {
          source = "src/_shared/scripts/open-mail";
          vars.TERM = constants.paths.term;
        };
        mail-unsubscribe.source = "src/aerc/scripts/unsubscribe";
        mail-pager.source = "src/aerc/scripts/nvim-pager.sh";
        monitor-brightness.source = "src/_shared/scripts/monitor.brightness.sh";
        screen-record.source = "src/_shared/scripts/screen-record.sh";
        waybar-launch.source = "src/_shared/scripts/waybar.launch.sh";
        power-profile-fix = {
          source = "src/_shared/scripts/power.profile.fix.sh";
          # Must match modules/nixos/polkit.nix and the activation module —
          # pkexec canonicalises symlinks, so the polkit rule and this
          # script point at the same content-addressed path.
          vars.HELPER_PATH = homeLib.powerProfileHelperPath;
        };
        # bin/hm and bin/nixos-iso are templated against absolute store
        # paths for sops/age/ssh-to-age so the wrapper doesn't depend on
        # whatever happens to be on $PATH at invocation time.
        hm = {
          source = "bin/hm";
          vars = {
            FLAKE_DIR = flakeDir;
            SOPS = "${pkgs.sops}/bin/sops";
            AGE = "${pkgs.age}/bin/age";
            SSH_TO_AGE = "${pkgs.ssh-to-age}/bin/ssh-to-age";
          };
        };
        nixos-iso = {
          source = "bin/nixos-iso";
          vars.FLAKE_DIR = flakeDir;
        };
      };

      scripts = binScripts // srcScripts;

      # `hm` and `nixos-iso` are essential CLI on every host (this matches
      # how they were installed before the refactor — directly via
      # home.packages with no feature gate). Everything else is
      # desktop-tied (waybar launcher, brightness, mail helpers, …).
      unconditionalNames = [
        "hm"
        "nixos-iso"
      ];
      isUnconditional = name: builtins.elem name unconditionalNames;
      unconditionalScripts =
        lib.attrValues (lib.filterAttrs (n: _: isUnconditional n) scripts);
      desktopScripts =
        lib.attrValues (lib.filterAttrs (n: _: !(isUnconditional n)) scripts);
    in
    {
      _module.args.scripts = scripts;
      home.packages =
        unconditionalScripts
        ++ lib.optionals config.features.desktop desktopScripts;
    };
}
