_:
let
  order = import ./_order.nix;
in
{
  flake.modules.homeManager.activationSetupNodeCaBundle =
    {
      config,
      lib,
      ...
    }:
    let
      bundlePath = config.home.sessionVariables.NODE_EXTRA_CA_CERTS;
      bundleDir = builtins.dirOf bundlePath;
    in
    {
      home.activation.setupNodeCaBundle = lib.hm.dag.entryAfter order.after.setupNodeCaBundle ''
        bundle="${bundlePath}"
        bundle_dir="${bundleDir}"
        tmp="$bundle.tmp"

        mkdir -p "$bundle_dir"
        : > "$tmp"

        add_file() {
          [ -f "$1" ] && cat "$1" >> "$tmp"
        }

        add_dir() {
          [ -d "$1" ] || return 0
          for f in "$1"/*.pem "$1"/*.crt "$1"/*.cer; do
            [ -f "$f" ] && cat "$f" >> "$tmp"
          done
        }

        if [ -n "''${CAROOT-}" ]; then
          add_file "''${CAROOT}/rootCA.pem"
        fi

        if command -v mkcert >/dev/null 2>&1; then
          caroot="$(mkcert -CAROOT 2>/dev/null || true)"
          [ -n "$caroot" ] && add_file "$caroot/rootCA.pem"
        fi

        add_dir "$HOME/.valet/CA"
        add_dir "$HOME/.config/valet/CA"

        mv "$tmp" "$bundle"
      '';
    };
}
