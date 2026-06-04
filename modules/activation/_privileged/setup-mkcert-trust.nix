_: {
  # Trust the mkcert development root CA on non-NixOS hosts.
  #
  # `srv` generates per-site certificates signed by the mkcert root CA
  # (~/.local/share/mkcert/rootCA.pem), but nothing trusts that CA until
  # `mkcert -install` has run — so https://start.local fails with "unable
  # to get local issuer certificate". On NixOS modules/nixos/mkcert.nix
  # wires the CA into security.pki.certificateFiles; this is the
  # Ubuntu/Debian/Fedora equivalent. `mkcert -install` covers both the
  # system trust store (/usr/local/share/ca-certificates →
  # update-ca-certificates) and the browser NSS databases.
  enableIf = { config, ... }: config.features.srv;
  args =
    {
      config,
      pkgs,
      homeLib,
      ...
    }:
    let
      rootCA = "${config.home.homeDirectory}/.local/share/mkcert/rootCA.pem";
    in
    homeLib.mkInstallPrompt {
      subject = "the mkcert root CA into the system & browser trust stores";
      body = ''
        Run `mkcert -install` to trust the mkcert development root CA
        (${rootCA}). This adds it to the system trust store
        (/usr/local/share/ca-certificates, via update-ca-certificates) and
        the browser NSS databases, so srv-served sites like
        https://start.local validate instead of failing with "unable to
        get local issuer certificate".

        On NixOS this CA is trusted via modules/nixos/mkcert.nix and this
        activation is gated off.
      '';
      # Skip until srv/mkcert has generated the root CA — the next switch
      # retries once it exists.
      preCheck = ''
        if [ ! -f "${rootCA}" ]; then
          echo "mkcert-trust: root CA not generated yet (run 'srv install'); skipping."
          exit 0
        fi
      '';
      # mkcert needs certutil (nss.tools) on PATH to reach the NSS stores;
      # without it the system store is still updated but browsers are not.
      # mkcert invokes sudo itself for the system store.
      actionScript = ''
        export PATH="${pkgs.nss.tools}/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
        ${pkgs.mkcert}/bin/mkcert -install
      '';
      # Re-run when the CA appears/disappears (regenerated, fresh OS install).
      stateInputs = [ rootCA ];
    };
}
