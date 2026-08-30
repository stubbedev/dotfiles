_:
let
  updateUrl = "https://clients2.google.com/service/update2/crx";

  # Force-installed extensions cannot be disabled or removed from within
  # Chrome — delete an entry here to un-manage it. SurfingKeys still needs its
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
  };
in
{
  stubbe.lib.chromePolicy = newtabUrl: {
    NewTabPageLocation = newtabUrl;
    HomepageLocation = newtabUrl;
    HomepageIsNewTabPage = false;

    HighEfficiencyModeEnabled = true;
    MemorySaverModeSavings = 2;

    ExtensionInstallForcelist = map (id: "${id};${updateUrl}") (builtins.attrNames extensions);
  };

  flake.modules.nixos.chromePolicy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.stubbe.userFeatures.browsers {
      environment.etc."opt/chrome/policies/managed/stubbedev-newtab.json".source =
        (pkgs.formats.json { }).generate "stubbedev-newtab.json"
          (pkgs.stubbe.chromePolicy pkgs.stubbe.newtabUrl);
    };
}
