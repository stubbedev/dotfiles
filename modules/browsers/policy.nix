_:
let
  updateUrl = "https://clients2.google.com/service/update2/crx";

  # Force-installed extensions cannot be disabled or removed from within
  # Chrome — delete an entry here to un-manage it. SurfingKeys still needs its
  # one-time "Allow access to file URLs" toggle granted by hand.
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
    # NewTabPageLocation drives both the new tab page and new windows (a new
    # window opens a new tab page). HomepageLocation points the home page and
    # the home button at the same minimal local page.
    NewTabPageLocation = newtabUrl;
    HomepageLocation = newtabUrl;
    HomepageIsNewTabPage = false;

    # Memory Saver: discard inactive background tabs to reclaim renderer RAM
    # (each open tab holds a live renderer process). HighEfficiencyMode is the
    # on/off toggle; MemorySaverModeSavings tunes aggressiveness (0 = longer
    # wait, 1 = balanced, 2 = max savings / discards sooner).
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
