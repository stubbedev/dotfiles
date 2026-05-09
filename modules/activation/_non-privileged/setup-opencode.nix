{ self, ... }: {
  enableIf = { config, ... }: config.features.opencode;
  args =
    {
      config,
      pkgs,
      homeLib,
      ...
    }:
    let
      configPath = "${config.home.homeDirectory}/.config/opencode/opencode.json";
      configDerivation = pkgs.writeText "opencode-config.json" (
        homeLib.substituteFile {
          file = self + "/src/opencode/opencode.json";
          vars = {
            CHROME_EXECUTABLE = "${config.home.profileDirectory}/bin/google-chrome-stable";
          };
        }
      );
    in
    {
      actionScript = ''
        mkdir -p "${config.home.homeDirectory}/.local/share/opencode"
        ln -sfn "${config.home.homeDirectory}/.local/share/opencode/opencode-local.db" "${config.home.homeDirectory}/.local/share/opencode/opencode.db"

        mkdir -p "$(dirname "${configPath}")"
        cp -f "${configDerivation}" "${configPath}"
      '';
    };
}
