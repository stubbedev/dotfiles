# Sudo-prompt scaffolding shared by all privileged activation setups.
# Produces consistent "Installing <subject>" prompts behind nh.
{ lib }:
{
  # Build the prompt fields from a single `subject`, then merge any
  # extra fields the caller supplies (preCheck, actionScript, body, …).
  # Title follows the "Installing <subject>" form, matching the most
  # common sudo-prompt setups.
  mkInstallPrompt =
    {
      subject,
      body,
      ...
    }@extra:
    removeAttrs extra [
      "subject"
      "body"
    ]
    // {
      promptTitle = "Installing ${subject}";
      promptBody = body;
    };

  sudoPromptScript =
    {
      pkgs,
      name,
      preCheck ? "",
      promptTitle,
      promptBody,
      actionScript,
      stateInputs ? [ ],
    }:
    let
      actionHash = builtins.hashString "sha256" actionScript;
      statePathsArg = lib.escapeShellArgs stateInputs;
    in
    pkgs.writeShellScript name ''
      set -e

      # nh pipes (and hides) activation output, so a switch sitting in a slow
      # action (update-initramfs, mkcert -install, …) looks hung. Write our
      # progress straight to the terminal when there is one. `[ -w /dev/tty ]`
      # is not enough: without a controlling terminal the node exists and
      # tests writable, but opening it fails ("No such device or address")
      # and set -e would abort the whole activation — so probe with a real
      # open in a subshell.
      if (exec >/dev/tty) 2>/dev/null; then
        exec >/dev/tty 2>&1
      fi

      SUDO=""
      for path in /bin/sudo /usr/bin/sudo /usr/local/bin/sudo; do
        if [ -x "$path" ]; then
          SUDO="$path"
          break
        fi
      done

      # We return if no sudo is found
      if [ -z "$SUDO" ]; then
        return 0
      fi

      sudo() { "$SUDO" "$@"; }

      # Fingerprint world-readable paths the script depends on so the lock
      # invalidates when those paths appear/disappear (e.g. a new display
      # manager getting installed after the script first ran).
      stateHash=$(
        for p in ${statePathsArg}; do
          if [ -e "$p" ]; then printf '%s:1\n' "$p"; else printf '%s:0\n' "$p"; fi
        done | sha256sum | cut -d' ' -f1
      )
      combinedHash="${actionHash}:$stateHash"

      lockFile="$HOME/.local/state/nix/home-manager/${name}.lock.sum"
      if [ -f "$lockFile" ] && [ "$(cat "$lockFile")" = "$combinedHash" ]; then
        exit 0
      fi

      ${preCheck}

      echo ""
      echo "--------------------------------------------------------------------"
      printf '%s\n' ${lib.escapeShellArg promptTitle}
      echo "--------------------------------------------------------------------"
      echo ""
      printf '%s\n' ${lib.escapeShellArg promptBody}

      # No confirmation prompt: activation runs behind nh, which pipes our
      # stdout/stderr, so a `read -p` blocks invisibly and the switch looks
      # hung. sudo itself still authenticates on /dev/tty when the timestamp
      # has expired, so the privilege gate stays interactive where it must be.
      ${actionScript}
      mkdir -p "$HOME/.local/state/nix/home-manager"
      echo -n "$combinedHash" > "$lockFile"
      echo ""
    '';
}
