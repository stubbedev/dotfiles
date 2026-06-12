_: {
  # Seed the browser NSS trust stores with the mkcert root CA on NixOS.
  #
  # On non-NixOS, modules/activation/_privileged/setup-mkcert-trust.nix runs
  # `mkcert -install`, which trusts the CA in BOTH the system store and the
  # browser NSS databases (Firefox/Chromium). That privileged activation is
  # gated off on NixOS (modules/activation/_helpers.nix only runs sudo
  # activations when host.platform != "nixos"), and modules/nixos/mkcert.nix
  # replaces only its *system*-store half via security.pki.certificateFiles.
  # Nothing seeds NSS — so https://start.local validates with curl (system
  # store) but Firefox/Chromium still reject it. This closes that gap.
  #
  # mkcert's NSS installer is unprivileged (the NSS dbs are user-owned), so
  # no sudo is needed; this lives in _non-privileged. TRUST_STORES=nss tells
  # mkcert to touch only NSS and skip the system store it would otherwise
  # try to sudo into (already handled by security.pki on NixOS).
  enableIf = { config, ... }: config.host.platform == "nixos" && (config.features.srv or false);
  args =
    { config, pkgs, ... }:
    let
      rootCA = "${config.home.homeDirectory}/.local/share/mkcert/rootCA.pem";
    in
    {
      actionScript = ''
        if [ -f "${rootCA}" ]; then
          # certutil (nss.tools) must be on PATH for mkcert to reach the
          # NSS stores; without it mkcert silently skips them.
          export PATH="${pkgs.nss.tools}/bin:$PATH"
          export TRUST_STORES=nss
          # Idempotent — runs every switch to catch new browser profiles or a
          # reset NSS db. Drop its "CA is (already) installed" chatter on
          # stdout; stderr still surfaces real failures.
          ${pkgs.mkcert}/bin/mkcert -install >/dev/null \
            || echo "mkcert-nss: 'mkcert -install' failed; browsers may not trust local certs." >&2
        else
          echo "mkcert-nss: root CA not generated yet (run 'srv install'); skipping." >&2
        fi
      '';
    };
}
