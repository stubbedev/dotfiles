_: {
  flake.modules.homeManager.packagesSlackWrappers =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      # Slack ships its own chrome-sandbox under lib/slack. From /nix/store
      # it can't be SUID, so the helper aborts. Pass --disable-setuid-sandbox
      # so Chromium falls back to the userns sandbox; the matching AppArmor
      # profile is installed by setup-slack-apparmor on Ubuntu 24.04+.
      slack-wrapped =
        let
          gfxSlack = homeLib.gfx pkgs.slack;
        in
        pkgs.runCommand "slack-no-suid"
          { nativeBuildInputs = [ pkgs.makeWrapper ]; }
          ''
            makeWrapper ${gfxSlack}/bin/slack $out/bin/slack \
              --add-flags "--disable-setuid-sandbox"
          '';

      slack-package = pkgs.symlinkJoin {
        name = "slack-${pkgs.slack.version}";
        paths = [
          slack-wrapped
          pkgs.slack
        ];
        meta = pkgs.slack.meta // {
          mainProgram = "slack";
        };
      };
    in
    lib.mkIf config.features.slack {
      home.packages = [ slack-package ];
    };
}
