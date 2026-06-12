_: {
  args =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      actionScript = ''
        # Activations run with a stripped PATH; awk (gawk) and find/xargs
        # (findutils) aren't on it. Without this the dedup awk pass below
        # fails with "awk: command not found" and the bundle is left as-is.
        export PATH="${
          lib.makeBinPath [
            pkgs.gawk
            pkgs.findutils
            pkgs.coreutils
          ]
        }:$PATH"

        bundle="${config.home.sessionVariables.NODE_EXTRA_CA_CERTS}"
        bundle_dir="${builtins.dirOf config.home.sessionVariables.NODE_EXTRA_CA_CERTS}"
        tmp="$bundle.tmp"

        mkdir -p "$bundle_dir"
        : > "$tmp"

        add_file() {
          [ -f "$1" ] || return 0
          cat "$1" >> "$tmp"
        }

        add_dir() {
          [ -d "$1" ] || return 0
          find "$1" -maxdepth 1 \( -name '*.pem' -o -name '*.crt' -o -name '*.cer' \) -type f -print0 |
            xargs -0 -r cat >> "$tmp"
        }

        add_valet_paths() {
          for dir in \
            "$HOME/.valet" \
            "$HOME/.config/valet" \
            "''${XDG_DATA_HOME:-$HOME/.local/share}/valet" \
            "''${XDG_CONFIG_HOME:-$HOME/.config}/valet"; do
            [ -d "$dir" ] || continue
            add_dir "$dir/CA"
            add_dir "$dir/Certificates"
          done
        }

        add_srv_paths() {
          add_file "''${XDG_DATA_HOME:-$HOME/.local/share}/mkcert/rootCA.pem"
          local sites_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/srv/sites"
          [ -d "$sites_dir" ] || return 0
          for site_dir in "$sites_dir"/*/; do
            add_dir "$site_dir/certs"
          done
        }

        # 1. OS trust store — always present, valid PEM, and already includes
        #    the mkcert CA. Seeding with it guarantees a non-empty bundle so the
        #    runtime (BoringSSL, via Claude Code) never warns at launch:
        #    a missing file fails with errno 2 ("system library"), an empty one
        #    with "PEM routines".
        add_file "${config.home.sessionVariables.SSL_CERT_FILE}"

        # 2. mkcert root, in case the OS store predates the current CA.
        if [ -n "''${CAROOT-}" ]; then
          add_file "''${CAROOT}/rootCA.pem"
        fi
        if command -v mkcert >/dev/null 2>&1; then
          caroot="$(mkcert -CAROOT 2>/dev/null || true)"
          [ -n "$caroot" ] && add_file "$caroot/rootCA.pem"
        fi

        # 3. valet + srv leaf/CA certs (not present in the OS store).
        add_valet_paths
        ${lib.optionalString config.features.srv "add_srv_paths"}

        # Collapse to unique CERTIFICATE blocks, dropping comments and the
        # OS-store/mkcert-root overlap. BoringSSL stops at the first unparseable
        # block, so emit only clean cert PEM.
        awk '
          /-----BEGIN CERTIFICATE-----/ { inblk = 1; blk = "" }
          inblk { blk = blk $0 "\n" }
          /-----END CERTIFICATE-----/ { inblk = 0; if (!seen[blk]++) printf "%s", blk }
        ' "$tmp" > "$tmp.dedup" && mv "$tmp.dedup" "$tmp"

        # Publish only a non-empty result; otherwise keep the last good bundle
        # rather than leaving the path missing (which is what triggers the warn).
        if [ -s "$tmp" ]; then
          mv "$tmp" "$bundle"
        else
          rm -f "$tmp"
        fi
      '';
    };
}
