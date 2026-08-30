{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.lint-fix.program = pkgs.writeShellApplication {
        name = "lint-fix";
        runtimeInputs = [
          pkgs.statix
          pkgs.deadnix
          pkgs.nixfmt
          pkgs.git
        ];
        # Scoped to tracked files, which is exactly what ends up in the flake
        # source the checks run against. Walking `.` instead would follow the
        # result/ and .direnv symlinks into the read-only store.
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          statix fix .
          git ls-files -z '*.nix' \
            | xargs -0 deadnix --edit --
          git ls-files -z '*.nix' | xargs -0 nixfmt
        '';
      };

      checks = {
        # -c is required: statix reads statix.toml from the config path only,
        # and does not discover it inside the target directory.
        lint-statix = pkgs.runCommand "lint-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
          statix check -c ${self} ${self}
          touch "$out"
        '';

        lint-deadnix = pkgs.runCommand "lint-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail -- ${self}
          touch "$out"
        '';

        lint-fmt = pkgs.runCommand "lint-fmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          find ${self} -name '*.nix' -print0 | xargs -0 nixfmt --check
          touch "$out"
        '';

        lint-shellcheck = pkgs.runCommand "lint-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          shellcheck -S warning ${self}/bin/stb-install ${self}/bin/stb-install-nixos
          touch "$out"
        '';
      };
    };
}
