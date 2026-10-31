_:
let
  updateUrl = "https://clients2.google.com/service/update2/crx";

  # Force-installed extensions cannot be disabled or removed from within
  # Chrome — delete an entry here to un-manage it.
  extensions = {
    "gfbliohnnapiefjpjlpjnehglfpaknnc" = "SurfingKeys";
    "mbcjcnomlakhkechnbhmfjhnnllpbmlh" = "Tab Pinner (Keyboard Shortcuts)";
    "kbmfpngjjgdllneeigpgjifpgocmfgmb" = "Reddit Enhancement Suite";
    "hkedbapjpblbodpgbajblpnlpenaebaa" = "Elasticvue";
    "nngceckbapebfimnlniiiahkandclblb" = "Bitwarden Password Manager";
    "fmkadmapgofadopljbjfkapdkoienihi" = "React Developer Tools";
    "nebkdnlhchcbbjpgfmhifafhfjipphgi" = "Nuxt Assistant";
    "iaajmlceplecbljialhhkmedjlpdblhp" = "Vue.js devtools";
    "bcjindcccaagfpapjjmafapmmgkkhgoa" = "JSON Formatter";
    "mmlmfjhmonkocbjadbfplnigmagldckm" = "Playwright MCP Bridge";
  };

  policyTarget = "/etc/opt/chrome/policies/managed/stubbedev-newtab.json";

  policyFile =
    pkgs:
    pkgs.stubbe.gen.json "stubbedev-newtab.json" {
      NewTabPageLocation = pkgs.stubbe.newtabUrl;
      HomepageLocation = pkgs.stubbe.newtabUrl;
      HomepageIsNewTabPage = false;

      HighEfficiencyModeEnabled = true;
      MemorySaverModeSavings = 2;

      # Playwright MCP launches Chrome with
      # --disable-blink-features=AutomationControlled, which Chrome lists as an
      # unsupported flag. Keep the stealth flag, drop the infobar.
      CommandLineFlagSecurityWarningsEnabled = false;

      ExtensionInstallForcelist = map (id: "${id};${updateUrl}") (builtins.attrNames extensions);
    };
in
{
  flake.modules.nixos.chromePolicy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.browsers {
      environment.etc.${lib.removePrefix "/etc/" policyTarget}.source = policyFile pkgs;
    };

  flake.modules.homeManager.chromePolicy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.browsers {
      stubbe.setup.chromePolicy = {
        privileged = true;
        title = "Installing Chrome new-tab policy";
        body = ''
          Drop a Chrome enterprise policy at ${policyTarget}. It points the
          new tab page, new windows and the homepage at the local new-tab page
          (${pkgs.stubbe.newtabUrl}, served by srv), and force-installs the
          managed extensions (${lib.concatStringsSep ", " (builtins.attrValues extensions)}).
        '';
        script = pkgs.stubbe.setup.file {
          source = policyFile pkgs;
          target = policyTarget;
        };
      };
    };

  # Playwright's `chrome` channel probes exactly one path on Linux:
  # /opt/google/chrome/chrome. Point it at the Nix Chrome. L+ tracks store
  # path drift across switches.
  flake.modules.nixos.playwrightChrome =
    {
      config,
      lib,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.browsers {
      systemd.tmpfiles.rules = [
        "L+ /opt/google/chrome/chrome 0755 root root - ${
          config.home-manager.users.${config.host.primaryUser}.stubbe.chrome
        }/bin/google-chrome-stable"
      ];
    };
}
