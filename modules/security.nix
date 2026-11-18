{ inputs, ... }:
{
  flake.modules.nixos.security =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.lys.nixosModules.lys-secrets ];

      security.sudo = {
        wheelNeedsPassword = true;

        execWheelOnly = true;

        extraConfig = ''
          Defaults pwfeedback,lecture=never
        '';
      };

      services.lys-secrets = lib.mkIf config.stubbe.userFeatures.desktop {
        enable = true;
        package = pkgs.lys-secrets;
      };

      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-curses;
      };
    };

  flake.modules.nixos.polkit =
    { config, lib, ... }:
    let
      username = config.host.primaryUser;
    in
    {
      security.polkit.enable = true;

      environment.etc = {
        "polkit-1/rules.d/52-power-management.rules".text =
          let
            verbs = [
              "reboot"
              "reboot-ignore-inhibit"
              "power-off"
              "power-off-ignore-inhibit"
              "halt"
              "halt-ignore-inhibit"
              "suspend"
              "suspend-ignore-inhibit"
              "hibernate"
              "hibernate-ignore-inhibit"
              "hybrid-sleep"
              "suspend-then-hibernate"
            ];
            actions = map (v: "org.freedesktop.login1.${v}") (
              verbs
              ++ map (v: "${v}-multiple-sessions") (builtins.filter (v: !lib.hasSuffix "-ignore-inhibit" v) verbs)
            );
          in
          ''
            polkit.addRule(function(action, subject) {
              if (action.id.indexOf("org.freedesktop.login1.") !== 0) {
                return;
              }

              var allowed = ${builtins.toJSON (lib.genAttrs actions (_: true))};

              if (!allowed[action.id]) {
                return;
              }

              if (subject.user !== "${username}" || !subject.local || !subject.active) {
                return;
              }

              return polkit.Result.YES;
            });
          '';
      };
    };

  flake.modules.homeManager.security =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = lib.mkIf config.features.desktop [ pkgs.gnupg ];
    };
}
