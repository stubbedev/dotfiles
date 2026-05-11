_: {
  enableIf = { config, ... }: config.features.openssh;
  args = {
    actionScript = ''
      # Append the machine's own pubkey to its own authorized_keys so it
      # can ssh to itself (and so that a peer that shares the same key
      # pair can ssh in). Idempotent: grep skips when the line is
      # already present.
      pub="$HOME/.ssh/id_ed25519.pub"
      auth="$HOME/.ssh/authorized_keys"
      if [ -f "$pub" ]; then
        install -d -m 0700 "$HOME/.ssh"
        touch "$auth"
        chmod 600 "$auth"
        if ! grep -qxF "$(cat "$pub")" "$auth"; then
          cat "$pub" >> "$auth"
        fi
      fi
    '';
  };
}
