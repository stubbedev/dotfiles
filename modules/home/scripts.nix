{ self, ... }:
{
  flake.modules.homeManager.scripts =
    {
      config,
      lib,
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
      #   stb       personal CLI

      # Auto-discover everything under bin/ — name == filename. stb-install
      # is excluded; it's the pre-Nix bootstrap and runs from the checkout.
      binNames = lib.attrNames (
        lib.filterAttrs (name: type: type == "regular" && name != "stb-install") (
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
        waybar-launch.source = "src/_shared/scripts/waybar.launch.sh";
        power-profile-fix = {
          source = "src/_shared/scripts/power.profile.fix.sh";
          # Content-addressed store path: pkexec canonicalises symlinks, so
          # the polkit rule and this script must point at the exact same
          # absolute path. Keying on file content (not `self`) keeps the
          # path stable across rebuilds — using `self + "/..."` re-hashes
          # on every commit and triggers the sudo prompt in
          # setup-power-profile-fix.nix every `hm switch`. Must match
          # modules/nixos/polkit.nix and the activation module.
          vars.HELPER_PATH = toString (builtins.path {
            name = "power-profile-helper";
            path = self + "/src/_shared/scripts/power.profile.helper.sh";
          });
        };
      };

      scripts = binScripts // srcScripts;
    in
    {
      _module.args.scripts = scripts;
      home.packages = lib.mkIf config.features.desktop (builtins.attrValues scripts);
    };
}
