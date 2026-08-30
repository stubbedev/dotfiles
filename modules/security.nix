_: {
  flake.modules.nixos.security =
    { lib, pkgs, ... }:
    {
      security.sudo = {
        # Explicit policy: wheel members must enter their password. This is the
        # upstream default, declared here so a future module that pulls in
        # passwordless-wheel as a side effect cannot silently flip it off.
        wheelNeedsPassword = true;

        # Restrict the sudo binary's setuid bit to wheel members, so non-wheel
        # users cannot even invoke `sudo`. The primary user is in wheel
        # (modules/users.nix), so day-to-day sudo is unaffected.
        execWheelOnly = true;

        # Show '*' for each typed password character (sudo gives no echo at
        # all by default). Note: reveals password length to shoulder-surfers.
        extraConfig = ''
          Defaults pwfeedback
        '';
      };

      security.pam.services = {
        # /etc/pam.d/wayle is provisioned by the wayle NixOS module
        # (programs.wayle.lock.enable) as an empty service, since wayle locks
        # natively via ext-session-lock-v1. Merge the keyring hook in here: the
        # wayle unlock is the only place the login password is typed, so it is
        # the gate that must unlock the keyring — otherwise secret-service
        # clients (Chrome) prompt on first use each session.
        wayle.enableGnomeKeyring = true;

        # Keyring autounlock on both the tty-login and greetd PAM stacks.
        # greetd authenticates the graphical login under its own PAM service
        # ("greetd"), not "login", so both need the hook.
        login.enableGnomeKeyring = lib.mkDefault true;
        greetd.enableGnomeKeyring = true;
      };

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
      secretsExec =
        if builtins.pathExists /usr/bin/ksecretd then
          "/usr/bin/ksecretd"
        else if builtins.pathExists /usr/bin/gnome-keyring-daemon then
          "/usr/bin/gnome-keyring-daemon --start --foreground --components=secrets"
        else if builtins.pathExists /usr/bin/pass-secret-service then
          "/usr/bin/pass-secret-service"
        else
          null;
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

      # On a non-NixOS host the org.freedesktop.secrets provider is whatever the
      # distro installed, and nothing starts it under the compositor session —
      # so secret-service clients (Chrome, libsecret callers) find no backend.
      # Start whichever one exists, and only if the name is not already claimed.
      systemd.user.services = lib.mkIf (secretsExec != null && config.features.hyprland) {
        secrets-service = {
          Unit = {
            Description = "D-Bus secrets service (org.freedesktop.secrets)";
            After = [ "hyprland-session.target" ];
            PartOf = [ "hyprland-session.target" ];
          };
          Install.WantedBy = [ "hyprland-session.target" ];
          Service = {
            Type = "dbus";
            BusName = "org.freedesktop.secrets";
            ExecCondition = "/bin/sh -c '! ${lib.getExe' pkgs.systemd "busctl"} --user status org.freedesktop.secrets 2>/dev/null'";
            ExecStart = secretsExec;
            Restart = "on-failure";
            RestartSec = "2s";
          };
        };
      };

      stubbe.setup = {
        # The keyring literally named `login` is the only one PAM auto-unlocks
        # with the login password. But gnome-keyring hands secrets to clients
        # out of whatever keyring the `default` file names, and apps like Chrome
        # create and adopt their own keyring on first run, quietly stealing the
        # default slot. Once that happens the default keyring is no longer
        # PAM-unlocked, so every secret-service client prompts for a password
        # on first use each session.
        # Pin `default` back to `login`. PAM creates `login` itself on first
        # login when missing, so naming it ahead of time is safe. Unprivileged
        # and ungated by platform, so it runs on both targets. Takes effect on
        # the next login — a gnome-keyring-daemon already running keeps the
        # default it loaded at startup.
        keyringDefault = lib.mkIf config.features.desktop {
          script = ''
            keyringDir="${config.xdg.dataHome}/keyrings"
            defaultFile="$keyringDir/default"
            mkdir -p "$keyringDir"
            # The `default` file holds the bare keyring name with no trailing
            # newline (a 15-byte file reads back exactly "Default_Keyring").
            if [ "$(cat "$defaultFile" 2>/dev/null)" != "login" ]; then
              printf '%s' login > "$defaultFile"
              echo "keyring-default: pinned default keyring to 'login'."
            fi
          '';
        };

        keyringPam = lib.mkIf (config.features.hyprland || config.features.theming) {
          privileged = true;
          title = "GNOME Keyring PAM setup";
          body = ''
            This will add GNOME Keyring PAM lines to login session files
            to enable automatic keyring unlock on login.
          '';
          stateInputs = [
            "/etc/pam.d/login"
            "/etc/pam.d/ly"
            "/etc/pam.d/lightdm"
            "/etc/pam.d/gdm"
            "/etc/pam.d/greetd"
          ];
          script = ''
            authLine="auth optional pam_gnome_keyring.so"
            sessionLine="session optional pam_gnome_keyring.so auto_start"
            # The password line keeps the `login` keyring's password in sync
            # with the login password when it changes; without it autounlock
            # silently breaks after the next password change (PAM then feeds the
            # new password to a keyring still sealed with the old one). NixOS's
            # enableGnomeKeyring emits all three lines — match that here so both
            # targets configure PAM identically. `use_authtok` reuses the new
            # password pam_unix already collected earlier in the stack.
            passwordLine="password optional pam_gnome_keyring.so use_authtok"
            pamFiles=(
              /etc/pam.d/login
              /etc/pam.d/ly
              /etc/pam.d/lightdm
              /etc/pam.d/gdm
              /etc/pam.d/greetd
            )
            # Tolerant regex: distro-shipped lines like
            # `-auth   optional        pam_gnome_keyring.so` (dash prefix, tabs,
            # multi-space) escaped a literal-string match and we appended a
            # duplicate on every activation. Match any non-comment line in the
            # right phase that references pam_gnome_keyring.so.
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
        # NixOS provides. Without it, wayle's session-lock unlock cannot verify
        # the password at all.
        pamWrappers = lib.mkIf config.features.hyprland {
          privileged = true;
          title = "⚠️  Nix PAM wrapper setup required for wayle lock authentication";
          body = ''
            This will install a systemd service to enable password authentication
            for wayle's session lock. The service will persist across reboots.
          '';
          script = ''
            ${pkgs.stubbe.installText {
              name = "nix-pam-wrappers.service";
              target = "/etc/systemd/system/nix-pam-wrappers.service";
              text = lib.generators.toINI { listsAsDuplicateKeys = true; } {
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
            sudo systemctl daemon-reload
            sudo systemctl enable --now nix-pam-wrappers.service
          '';
        };
      };
    };
}
