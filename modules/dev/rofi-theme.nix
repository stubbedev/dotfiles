# The rasi writer in modules/core/pkgs/gen.nix is ours, so nothing but this
# check stands between a bad edit and rofi silently falling back to its
# built-in theme at runtime. Feeds the deployed files to rofi's own parser.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      deployed = self.homeConfigurations.stubbe.config.xdg.configFile;
      themeOf = name: deployed."rofi/${name}".source;
    in
    {
      checks.rofi-theme = pkgs.runCommand "check-rofi-theme" { nativeBuildInputs = [ pkgs.rofi ]; } ''
        set -euo pipefail

        # @import resolves relative to the theme's own directory, so the
        # palette has to sit next to the theme rofi is handed.
        dir="$(mktemp -d)"
        # Without a writable HOME rofi warns about its cache dir on every
        # run, and the stderr check below cannot tell that from a real
        # parse error.
        export HOME="$dir/home" XDG_CACHE_HOME="$dir/cache" XDG_RUNTIME_DIR="$dir/run"
        mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
        cp ${themeOf "catppuccin-mocha.rasi"} "$dir/catppuccin-mocha.rasi"
        cp ${themeOf "catppuccin-default.rasi"} "$dir/catppuccin-default.rasi"
        cp ${themeOf "config.rasi"} "$dir/config.rasi"

        for theme in catppuccin-default config; do
          if ! rofi -no-config -theme "$dir/$theme.rasi" -dump-theme >"$dir/$theme.dump" 2>"$dir/$theme.err"; then
            echo "rofi rejected the generated $theme.rasi:" >&2
            cat "$dir/$theme.err" >&2
            exit 1
          fi
          # rofi exits 0 on a theme it could not parse, reporting the
          # failure on stderr, so an empty error stream is the real signal.
          if [ -s "$dir/$theme.err" ]; then
            echo "rofi parsed $theme.rasi with errors:" >&2
            cat "$dir/$theme.err" >&2
            exit 1
          fi
        done

        # The palette must actually reach the theme: a broken @import
        # parses clean but drops every colour.
        grep -q "mauve" "$dir/catppuccin-default.dump" ||
          { echo "palette did not resolve into the theme" >&2; exit 1; }

        touch "$out"
      '';
    };
}
