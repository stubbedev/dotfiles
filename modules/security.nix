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
      imports = [ inputs.lys-secrets.nixosModules.default ];

      security.sudo = {
        wheelNeedsPassword = true;

        execWheelOnly = true;

        extraConfig = ''
          Defaults pwfeedback
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
      imports = [ inputs.lys-secrets.homeManagerModules.default ];

      services.lys-secrets = lib.mkIf (config.features.desktop && config.host.platform == "linux") {
        enable = true;
        package = pkgs.lys-secrets;
      };

      home.packages = lib.mkIf config.features.desktop [ pkgs.gnupg ];

      xdg.configFile = lib.mkIf config.services.lys-secrets.enable (
        lib.genAttrs
          [
            "systemd/user/gnome-keyring-daemon.service"
            "systemd/user/gnome-keyring-daemon.socket"
          ]
          (_: {
            source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
            force = true;
          })
      );

      stubbe.setup = {
        # Nix's PAM modules expect /run/wrappers/bin/unix_chkpwd, which only
        # NixOS provides. Without it, lys-shell's session-lock unlock cannot verify
        # the password at all.
        pamWrappers = lib.mkIf config.features.lysWm {
          privileged = true;
          title = "⚠️  Nix PAM wrapper setup required for lys-shell lock authentication";
          body = ''
            This will install a systemd service to enable password authentication
            for lys-shell's session lock. The service will persist across reboots.
          '';
          script = ''
            ${pkgs.stubbe.setup.text {
              name = "nix-pam-wrappers.service";
              target = "/etc/systemd/system/nix-pam-wrappers.service";
              text = pkgs.stubbe.gen.unitText {
                Unit = {
                  Description = "Setup Nix PAM wrappers for non-NixOS systems";
                  DefaultDependencies = "no";
                  Before = "sysinit.target";
                  ConditionPathExists = "!/run/wrappers/bin/unix_chkpwd";
                };
                Service = {
                  Type = "oneshot";
                  RemainAfterExit = "yes";
                  ExecStart = [
                    "/usr/bin/mkdir -p /run/wrappers/bin"
                    "/usr/bin/ln -sf /usr/sbin/unix_chkpwd /run/wrappers/bin/unix_chkpwd"
                  ];
                };
                Install.WantedBy = "sysinit.target";
              };
            }}
            ${pkgs.stubbe.setup.reloadUnits}
            sudo systemctl enable --now nix-pam-wrappers.service
          '';
        };
      };
    };
}
