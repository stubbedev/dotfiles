{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      nixLints = "SL8000-SL9000";

      withTrackedNixFiles = ''
        cd "$(git rev-parse --show-toplevel)"
        mapfile -d "" -t nix_files < <(
          git ls-files -z -- '*.nix' \
            | while IFS= read -r -d "" f; do
              if [ -e "$f" ]; then printf '%s\0' "$f"; fi
            done
        )
      '';

      nixTool =
        name: text:
        pkgs.stubbe.bashApp {
          inherit name text;
          runtimeInputs = [
            pkgs.shell-lsp
            pkgs.git
          ];
        };
    in
    {
      formatter = nixTool "nix-fmt" ''
        if [ "$#" -gt 0 ]; then
          exec shell-lsp fmt -w "$@"
        fi
        ${withTrackedNixFiles}
        shell-lsp fmt -w "''${nix_files[@]}"
      '';

      apps.lint-fix.program = nixTool "lint-fix" ''
        ${withTrackedNixFiles}
        patch=$(mktemp)
        trap 'rm -f "$patch"' EXIT
        status=0
        shell-lsp check -i ${nixLints} -f diff "''${nix_files[@]}" > "$patch" || status=$?
        if [ "$status" -gt 1 ]; then
          exit "$status"
        fi
        if [ -s "$patch" ]; then
          git apply "$patch"
        fi
        shell-lsp fmt -w "''${nix_files[@]}"
      '';

      checks = {
        lint-nix = pkgs.stubbe.check {
          name = "lint-nix";
          nativeBuildInputs = [ pkgs.shell-lsp ];
          text = ''
            cp -r --no-preserve=mode ${self} source
            shell-lsp check -i ${nixLints} -f gcc source
            touch "$out"
          '';
        };

        lint-fmt = pkgs.stubbe.check {
          name = "lint-fmt";
          nativeBuildInputs = [ pkgs.shell-lsp ];
          text = ''
            find ${self} -name '*.nix' -print0 | xargs -0 shell-lsp fmt -l
            touch "$out"
          '';
        };

        lint-shell = pkgs.stubbe.check {
          name = "lint-shell";
          nativeBuildInputs = [ pkgs.shell-lsp ];
          text = ''
            shell-lsp check -S warning ${self}/bin/*
            touch "$out"
          '';
        };
      };
    };
}
