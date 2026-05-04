_: {
  enableIf = { config, ... }: config.features.desktop;
  args = _: {
    preCheck = ''
      PATH="/sbin:/usr/sbin:$PATH"
      if ! command -v apparmor_status >/dev/null 2>&1; then
        exit 0
      fi
    '';
    promptTitle = "Installing AppArmor profile for Nix-installed Logseq";
    promptBody = ''
      Ubuntu 24.04 restricts unprivileged user namespaces (required by
      Chromium-based sandboxes) to binaries with a matching AppArmor
      profile. Nix-store paths aren't covered by Ubuntu's stock profiles,
      so Logseq aborts on launch with "No usable sandbox!".

      This installs an AppArmor profile that whitelists the Nix-store
      Electron binary used by Logseq for unprivileged userns.
    '';
    promptQuestion = "Install AppArmor profile for Nix Logseq?";
    actionScript = ''
      tmpfile=$(mktemp)
      trap 'rm -f "$tmpfile"' EXIT
      cat > "$tmpfile" << 'EOF'
      # managed-by: home-manager logseq-apparmor v1
      abi <abi/4.0>,
      include <tunables/global>
      profile nix-logseq /nix/store/*-electron*/libexec/electron/{electron,chrome-sandbox} flags=(unconfined) {
        userns,
        @{exec_path} mr,
        include if exists <local/nix-logseq>
      }
      EOF
      sudo install -m 0644 "$tmpfile" /etc/apparmor.d/nix-logseq
      sudo chown root:root /etc/apparmor.d/nix-logseq
      sudo apparmor_parser -r /etc/apparmor.d/nix-logseq
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
