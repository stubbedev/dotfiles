_: {
  flake.modules.nixos.security =
    { lib, pkgs, ... }:
    {
      security.sudo = {
        wheelNeedsPassword = true;

        execWheelOnly = true;

        extraConfig = ''
          Defaults pwfeedback
        '';
      };

      security.pam.services.login.enableGnomeKeyring = lib.mkDefault true;

      services.gnome.gnome-keyring.enable = true;

      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-gnome3;
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
    in
    {
      home.packages = lib.mkIf config.features.desktop (
        with pkgs;
        [
          gnupg
          pinentry-gnome3 # Wayland-compatible pinentry for GPG
          gcr_4 # provides gcr-prompter
          libsecret # `secret-tool` and the client library
          gnome-keyring # the org.freedesktop.secrets daemon
          seahorse # GUI keyring manager
        ]
      );

      stubbe.setup = {
        # The keyring literally named `login` is the only one PAM auto-unlocks
        # with the login password. But gnome-keyring hands secrets to clients
        # out of whatever keyring the `default` file names, and apps like Chrome
        # create and adopt their own keyring on first run, quietly stealing the
        # default slot. Once that happens the default keyring is no longer
        # PAM-unlocked, so every secret-service client prompts for a password
        # on first use each session.
        keyringDefault = lib.mkIf config.features.desktop {
          script = ''
            keyringDir="${config.xdg.dataHome}/keyrings"
            defaultFile="$keyringDir/default"
            mkdir -p "$keyringDir"
            if [ "$(cat "$defaultFile" 2>/dev/null)" != "login" ]; then
              printf '%s' login > "$defaultFile"
              echo "keyring-default: pinned default keyring to 'login'."
            fi
          '';
        };

        keyringPam = lib.mkIf config.features.desktop {
          privileged = true;
          title = "GNOME Keyring PAM setup";
          body = ''
            This will add GNOME Keyring PAM lines to login session files
            to enable automatic keyring unlock on login.
          '';
          stateInputs = pamFiles;
          script = ''
            authLine="auth optional pam_gnome_keyring.so"
            sessionLine="session optional pam_gnome_keyring.so auto_start"
            passwordLine="password optional pam_gnome_keyring.so use_authtok"
            pamFiles=(${lib.escapeShellArgs pamFiles})
            hasPhase() {
              local file="$1" phase="$2"
              grep -qE "^[[:space:]]*-?''${phase}[[:space:]]+\S+[[:space:]]+.*pam_gnome_keyring\.so" "$file"
            }
            for file in "''${pamFiles[@]}"; do
              [ -f "$file" ] || continue
              hasPhase "$file" auth     || printf '%s\n' "$authLine"     | sudo tee -a "$file" > /dev/null
              hasPhase "$file" session  || printf '%s\n' "$sessionLine"  | sudo tee -a "$file" > /dev/null
              hasPhase "$file" password || printf '%s\n' "$passwordLine" | sudo tee -a "$file" > /dev/null
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
