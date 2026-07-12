{ self, ... }:
{
  # api.github.com caps anonymous requests at 60/hr per IP. `nix flake
  # update` resolves every input's HEAD against that API, so a flake with
  # ~20 github inputs exhausts the budget in one run and falls back to
  # stale cached revs (the "HTTP error 403 … rate limit exceeded … using
  # cached version" wall). An access token lifts the cap to 5000/hr.
  #
  # This is the non-NixOS path: HM owns /etc/nix here. The token is
  # decrypted at activation from secrets/github-token (NOT baked into the
  # script — only its ciphertext hash is, so a rotate/edit re-triggers the
  # otherwise-locked activation) and written to a root-owned include file.
  # The matching NixOS path lives in modules/nixos/nix-settings.nix.
  args =
    { config, ... }:
    let
      # sudoPromptScript hashes actionScript to gate the sudo prompt: if the
      # text is byte-identical to last run, the lock holds and we skip. So
      # actionScript MUST NOT embed anything that churns between switches —
      # baking ${self} (new store path every commit/dirty tree) or
      # ${pkgs.sops} (new path on every nixpkgs bump) re-prompts on EVERY
      # switch. Two stable references instead:
      #
      #   secretPath — content-addressed copy of the ciphertext. Hashes the
      #     file's *contents*, not the flake source, so it's invariant across
      #     commits but DOES change when the token is re-encrypted
      #     (hm secret rotate/edit/set) — exactly when we want a re-prompt.
      #     Same trick as lib.nix:powerProfileHelperPath.
      #   profileBin — ~/.nix-profile/bin (a fixed string), where sops +
      #     ssh-to-age live via modules/sops.nix's home.packages. Stable
      #     across nixpkgs bumps, unlike ${pkgs.sops}.
      secretPath = toString (
        builtins.path {
          name = "github-token";
          path = self + "/secrets/github-token";
        }
      );
      profileBin = "${config.home.profileDirectory}/bin";
    in
    {
      preCheck = ''
        PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
        # No nix → nothing to configure.
        if ! command -v nix >/dev/null 2>&1; then
          exit 0
        fi
        # The age identity is derived from the SSH key; without it we can't
        # decrypt. Skip silently rather than prompt for sudo we can't use.
        if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
          exit 0
        fi
      '';
      promptTitle = "GitHub access token for Nix flake fetches";
      promptBody = ''
        Writes `access-tokens = github.com=<token>` to
        /etc/nix/nix-access-tokens.conf (root:<your-group>, 0640) and pulls
        it into /etc/nix/nix.conf via `!include`, so `nix flake update`
        authenticates to the GitHub API (60 req/hr anonymous → 5000 req/hr).

        The token is decrypted from secrets/github-token at activation; it
        never lands in the Nix store or in the activation script.
      '';
      actionScript = ''
        # Derive the age identity straight from the SSH key (same path
        # sops-nix uses) so this doesn't depend on ~/.config/sops/age/keys.txt
        # having been materialised yet — its activation runs after ours.
        ageKey=$(${profileBin}/ssh-to-age -private-key -i "$HOME/.ssh/id_ed25519")
        token=$(SOPS_AGE_KEY="$ageKey" ${profileBin}/sops --decrypt \
          --input-type binary --output-type binary \
          "${secretPath}" | tr -d '\n')
        unset ageKey

        if [ -z "$token" ]; then
          echo "nix-github-token: decrypted token is empty, aborting." >&2
          exit 1
        fi

        # root-owned, but group = the invoking user so their unprivileged
        # `nix flake update` can still read it (0640). Write via a 0077-umask
        # tmp file then `install` so the token is never world-readable, even
        # for the instant before chmod.
        grp=$(id -gn)
        umask 077
        tmp=$(mktemp)
        printf 'access-tokens = github.com=%s\n' "$token" > "$tmp"
        unset token
        sudo install -m 0640 -o root -g "$grp" "$tmp" /etc/nix/nix-access-tokens.conf
        rm -f "$tmp"

        # Reference it from the main config. `!include` (leading bang) is the
        # optional form: no error if the file is later removed. Appended once,
        # idempotently — the installer-managed nix.conf is left otherwise
        # untouched. Relative path resolves against /etc/nix.
        if ! grep -qxF '!include nix-access-tokens.conf' /etc/nix/nix.conf 2>/dev/null; then
          printf '\n# managed-by: home-manager nix-github-token\n!include nix-access-tokens.conf\n' \
            | sudo tee -a /etc/nix/nix.conf >/dev/null
        fi
      '';
    };
}
