{ self, inputs, ... }:
{
  flake.modules.nixos.polkit =
    { lib, ... }:
    let
      homeLib = import (self + "/lib.nix") { inherit (inputs.nixpkgs) lib; inherit self; };

      username = "stubbe";
      # NixOS with useUserPackages places the home-manager profile at
      # /etc/profiles/per-user/<user>; this mirrors config.home.profileDirectory
      # used in the standalone-HM activation (setup-vpn-polkit.nix).
      profileDir = "/etc/profiles/per-user/${username}";
      # pkexec resolves symlinks before matching allowedPrograms. Reference
      # the helper via the flake's Nix store source path so both the polkit
      # rule and the live script (modules/home/scripts.nix) point at the
      # same canonical path. Resolving via ~/.stubbe or /etc/nixos depends
      # on per-host symlinks that aren't guaranteed to exist or to resolve
      # to the same target — store paths always do.
      helperPath = toString (self + "/src/_shared/scripts/power.profile.helper.sh");
    in
    {
      security.polkit.enable = true;

      # Polkit rule files are parsed in lexical order; the file names match
      # what the non-NixOS activation scripts install under /etc/polkit-1/rules.d/.
      environment.etc."polkit-1/rules.d/49-openconnect.rules".text = homeLib.substituteFile {
        file = self + "/src/polkit/49-openconnect.rules";
        vars = {
          USERNAME = username;
          PROFILE_DIR = profileDir;
        };
      };

      environment.etc."polkit-1/rules.d/50-power-profile-fix.rules".text = homeLib.substituteFile {
        file = self + "/src/polkit/50-power-profile-fix.rules";
        vars = {
          USERNAME = username;
          HELPER_PATH = helperPath;
        };
      };

      environment.etc."polkit-1/rules.d/52-power-management.rules".text = homeLib.substituteFile {
        file = self + "/src/polkit/52-power-management.rules";
        vars = {
          USERNAME = username;
        };
      };
    };
}
