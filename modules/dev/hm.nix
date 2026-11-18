{ referenceHome, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks.hm = pkgs.stubbe.check {
        name = "hm";
        timeout = 60;
        nativeBuildInputs = [ pkgs.stubbe.hm ];
        env.hmConfig = pkgs.writeText "hm-config.yaml" (
          builtins.unsafeDiscardStringContext (builtins.toJSON referenceHome.stubbe.hm.settings)
        );
        text = ''
          export HM_CONFIG="$hmConfig" HM_FLAKE_DIR="$PWD"
          help=$(hm help)
          ${lib.concatMapStrings (command: ''
            [[ "$help" == *${lib.escapeShellArg "  ${command.name} "}* ]] ||
              { echo "checks.hm: hm help lists no ${command.name} command for the reference home" >&2; exit 1; }
          '') referenceHome.stubbe.hm.commands}
          touch "$out"
        '';
      };
    };
}
