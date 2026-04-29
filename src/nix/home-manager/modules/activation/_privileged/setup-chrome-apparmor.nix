_: {
  enableIf = { config, ... }: config.features.browsers;
  args = _: {
    preCheck = ''
      PATH="/sbin:/usr/sbin:$PATH"
      if ! command -v apparmor_status >/dev/null 2>&1; then
        exit 0
      fi
    '';
    promptTitle = "Installing AppArmor profile for Nix-installed Chrome";
    promptBody = ''
      Ubuntu 24.04 restricts unprivileged user namespaces (required by
      Chrome's sandbox) to binaries with a matching AppArmor profile.
      Nix-store paths aren't covered by Ubuntu's stock chrome profile,
      so Chrome aborts on launch with "No usable sandbox!".

      This installs an AppArmor profile that whitelists the Nix-store
      Chrome binary (and its sandbox helper) for unprivileged userns.
    '';
    promptQuestion = "Install AppArmor profile for Nix Chrome?";
    actionScript = ''
      tmpfile=$(mktemp)
      trap 'rm -f "$tmpfile"' EXIT
      cat > "$tmpfile" << 'EOF'
      # managed-by: home-manager chrome-apparmor v1
      abi <abi/4.0>,
      include <tunables/global>
      profile nix-google-chrome-stable /nix/store/*/share/google/chrome/{chrome,chrome-sandbox} flags=(unconfined) {
        userns,
        @{exec_path} mr,
        include if exists <local/nix-google-chrome-stable>
      }
      EOF
      sudo install -m 0644 "$tmpfile" /etc/apparmor.d/nix-google-chrome-stable
      sudo chown root:root /etc/apparmor.d/nix-google-chrome-stable
      sudo apparmor_parser -r /etc/apparmor.d/nix-google-chrome-stable
    '';
    skipMessage = "Skipped. You can install it later by running: home-manager switch --flake . --impure";
  };
}
