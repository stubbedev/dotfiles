# Nothing bespoke is deployed any more: modules/rofi.nix hands attrsets to
# programs.rofi, which renders config.rasi and the theme. This check still
# feeds the rendered pair to rofi the way rofi loads them at runtime, so a
# bad attrset cannot ship a theme rofi silently falls back from.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      hm = self.homeConfigurations.stubbe.config;
      themeRasi = hm.xdg.dataFile."rofi/themes/custom.rasi".source;
      configRasi = hm.home.file."${hm.programs.rofi.configPath}".source;
    in
    {
      checks.rofi-theme = pkgs.stubbe.check {
        name = "rofi-theme";
        nativeBuildInputs = [ pkgs.rofi ];
        text = ''
          set -euo pipefail

          dir="$(mktemp -d)"
          # Without a writable HOME rofi warns about its cache dir on every
          # run, and the stderr check below cannot tell that from a real
          # parse error.
          export HOME="$dir/home" XDG_CACHE_HOME="$dir/cache" XDG_RUNTIME_DIR="$dir/run"
          export XDG_CONFIG_HOME="$dir" XDG_DATA_HOME="$dir/data"
          mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
          # The layout rofi sees at runtime: config.rasi under
          # XDG_CONFIG_HOME, its @theme "custom" resolving from rofi's theme
          # search path.
          install -D ${configRasi} "$dir/rofi/config.rasi"
          install -D ${themeRasi} "$dir/data/rofi/themes/custom.rasi"

          if ! rofi -dump-theme >"$dir/dump" 2>"$dir/err"; then
            echo "rofi rejected the rendered config or theme:" >&2
            cat "$dir/err" >&2
            exit 1
          fi
          # rofi exits 0 on a file it could not parse, reporting the
          # failure on stderr, so an empty error stream is the real signal.
          if [ -s "$dir/err" ]; then
            echo "rofi parsed the rendered config or theme with errors:" >&2
            cat "$dir/err" >&2
            exit 1
          fi

          for section in window mainbox inputbar listview element-text; do
            grep -q "^$section {" "$dir/data/rofi/themes/custom.rasi" ||
              { echo "missing section: $section" >&2; exit 1; }
          done

          # The palette must actually reach the theme: a misrouted file
          # parses clean but drops every colour.
          grep -q "mauve" "$dir/dump" ||
            { echo "palette did not resolve into the theme" >&2; exit 1; }

          touch "$out"
        '';
      };
    };
}
