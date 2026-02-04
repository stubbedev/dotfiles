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

        if [ -n "''${CAROOT-}" ]; then
          add_file "''${CAROOT}/rootCA.pem"
        fi

        if command -v mkcert >/dev/null 2>&1; then
          caroot="$(mkcert -CAROOT 2>/dev/null || true)"
          [ -n "$caroot" ] && add_file "$caroot/rootCA.pem"
        fi

        add_valet_paths

        mv "$tmp" "$bundle"
      '';
    };
}
