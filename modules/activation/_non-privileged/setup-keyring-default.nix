_: {
  # The keyring literally named `login` is the only one PAM auto-unlocks
  # with the login password — see modules/nixos/pam.nix (NixOS) and
  # modules/activation/_privileged/setup-keyring-pam.nix (non-NixOS). But
  # gnome-keyring hands secrets to clients out of whatever keyring the
  # `default` file names, and apps like Chrome create + adopt their own
  # keyring on first run, quietly stealing the default slot. Once that
  # happens the default keyring is no longer PAM-unlocked, so every
  # secret-service client prompts for a password on first use each session.
  #
  # Pin `default` back to `login` so the autounlocked keyring is always the
  # one clients reach for. PAM creates `login` itself on first login when it
  # is missing, so naming it ahead of time is safe. This is a non-privileged
  # module (mkSetupModule, no platform gate) so it runs on both NixOS and
  # standalone home-manager. Takes effect on the next login — a
  # gnome-keyring-daemon already running this session keeps the default it
  # loaded at startup until then.
  enableIf = { config, ... }: config.features.desktop;
  args =
    { config, ... }:
    {
      actionScript = ''
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
}
