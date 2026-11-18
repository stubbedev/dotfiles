{ referenceHome, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks.hix = pkgs.stubbe.check {
        name = "hix";
        timeout = 60;
        nativeBuildInputs = [ referenceHome.programs.hix.package ];
        env.hixConfig = referenceHome.xdg.configFile."hix/config.yaml".source;
        text = ''
          export HIX_CONFIG="$hixConfig" HIX_FLAKE_DIR="$PWD"
          help=$(hix help)
          ${lib.concatMapStrings (command: ''
            [[ "$help" == *${lib.escapeShellArg "  ${command.name} "}* ]] ||
              { echo "checks.hix: hix help lists no ${command.name} command for the reference home" >&2; exit 1; }
          '') referenceHome.programs.hix.commands}
          touch "$out"
        '';
      };
    };
}
