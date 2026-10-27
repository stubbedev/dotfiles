{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      configYaml = self.homeConfigurations.stubbe.config.xdg.configFile."lys-wm/config.yaml".source;
    in
    {
      checks.lys-wm-config = pkgs.stubbe.check {
        name = "lys-wm-config";
        timeout = 60;
        nativeBuildInputs = [ pkgs.lys-wm ];
        text = ''
          set -euo pipefail

          dir="$(mktemp -d)"
          export HOME="$dir/home" XDG_RUNTIME_DIR="$dir/run"
          mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
          unset WAYLAND_DISPLAY

          lys-wm --backend headless --config ${configYaml} >"$dir/log" 2>&1 &
          pid=$!

          for _ in $(seq 100); do
            if lys-wmctl version >/dev/null 2>&1; then
              kill "$pid"
              wait "$pid" || [ "$?" -eq 143 ]
              touch "$out"
              exit 0
            fi
            if ! kill -0 "$pid" 2>/dev/null; then
              echo "lys-wm rejected the rendered config:" >&2
              cat "$dir/log" >&2
              exit 1
            fi
            sleep 0.1
          done

          echo "lys-wm did not answer on its IPC socket within 10s:" >&2
          cat "$dir/log" >&2
          exit 1
        '';
      };
    };
}
