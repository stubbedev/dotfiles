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
    let
      pamFiles = [
        "/etc/pam.d/login"
        "/etc/pam.d/ly"
        "/etc/pam.d/lightdm"
        "/etc/pam.d/gdm"
      ];

      keyringMigrate = pkgs.stubbe.keyringMigrate { };
    in
    {
      imports = [ inputs.lys-secrets.homeManagerModules.default ];

      services.lys-secrets = lib.mkIf (config.features.desktop && config.host.platform == "linux") {
        enable = true;
        package = pkgs.lys-secrets;
      };

      home.packages = lib.mkIf config.features.desktop [
        pkgs.gnupg
        keyringMigrate
      ];

      stubbe.setup = {
        lysSecrets = lib.mkIf config.features.desktop {
          privileged = true;
          title = "Moving to lys-secrets (in place of gnome-keyring)";
          body = ''
            Copy every secret from the gnome-keyring login keyring into lys-secrets
            and verify each one, so Chrome, Slack and the rest keep working. This
            asks for your login password. The old keyring file is left untouched.

            Then stop gnome-keyring from claiming org.freedesktop.secrets at the
            next login: mask its user units and remove the PAM lines this repo
            added. It keeps running until you log out.
          '';
          script = ''
            ${lib.getExe keyringMigrate}

            unit_dir="${config.xdg.configHome}/systemd/user"
            mkdir -p "$unit_dir"
            ln -sfT /dev/null "$unit_dir/gnome-keyring-daemon.service"
            ln -sfT /dev/null "$unit_dir/gnome-keyring-daemon.socket"

            for file in ${lib.escapeShellArgs pamFiles}; do
              if [ -f "$file" ]; then
                sudo sed -i \
                  -e '/^auth optional pam_gnome_keyring\.so$/d' \
                  -e '/^session optional pam_gnome_keyring\.so auto_start$/d' \
                  -e '/^password optional pam_gnome_keyring\.so use_authtok$/d' \
                  "$file"
              fi
            done
          '';
        };

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
