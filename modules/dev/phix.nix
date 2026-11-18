{ referenceHome, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks.phix = pkgs.stubbe.check {
        name = "phix";
        timeout = 60;
        nativeBuildInputs = [ referenceHome.programs.phix.package ];
        env.phixConfig = referenceHome.xdg.configFile."phix/config.yaml".source;
        text = ''
          export PHIX_CONFIG="$phixConfig" PHIX_FLAKE_DIR="$PWD"
          help=$(phix help)
          ${lib.concatMapStrings (command: ''
            [[ "$help" == *${lib.escapeShellArg "  ${command.name} "}* ]] ||
              { echo "checks.phix: phix help lists no ${command.name} command for the reference home" >&2; exit 1; }
          '') referenceHome.programs.phix.commands}
          touch "$out"
        '';
      };
    };
}
