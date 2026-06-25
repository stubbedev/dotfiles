# Shared Chrome enterprise-policy body. The leading underscore keeps
# import-tree from loading it as a flake module; it is imported directly
# by both Chrome policy modules so the policy has a single source:
#   modules/activation/_privileged/setup-chrome-policy.nix  (non-NixOS)
#   modules/nixos/chrome-policy.nix                         (NixOS)
#
# Chrome reads these from /etc/opt/chrome/policies/managed/.
{ newtabUrl }:
let
  # Chrome Web Store update endpoint, used by every force-installed entry.
  updateUrl = "https://clients2.google.com/service/update2/crx";

  # Extensions force-installed from the Chrome Web Store, id -> name.
  # Force-installed extensions cannot be disabled or removed from within
  # Chrome — delete an entry here to un-manage it. SurfingKeys still needs
  # its one-time "Allow access to file URLs" toggle granted by hand.
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
  # NewTabPageLocation drives both the new tab page and new windows
  # (a new window opens a new tab page). HomepageLocation points the
  # home page / home button at the same minimal local page.
  NewTabPageLocation = newtabUrl;
  HomepageLocation = newtabUrl;
  HomepageIsNewTabPage = false;

  # Memory Saver: discard inactive background tabs to reclaim renderer RAM
  # (each open tab/site holds a live renderer process). HighEfficiencyMode
  # is the on/off toggle; MemorySaverModeSavings tunes aggressiveness
  # (0 longer wait, 1 balanced, 2 max savings / discards sooner).
  HighEfficiencyModeEnabled = true;
  MemorySaverModeSavings = 2;

  ExtensionInstallForcelist = map (id: "${id};${updateUrl}") (builtins.attrNames extensions);
}
