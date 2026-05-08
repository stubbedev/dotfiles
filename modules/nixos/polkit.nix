{ self, inputs, ... }:
{
  flake.modules.nixos.polkit =
    { lib, ... }:
    let
      homeLib = import (self + "/lib.nix") { inherit (inputs.nixpkgs) lib; inherit self; };

      username = "stubbe";
      home = "/home/${username}";
      # pkexec resolves symlinks before matching allowedPrograms.
      # ~/.stubbe is a symlink → /etc/nixos (the live flake checkout), so the
      # canonical path pkexec sees is /etc/nixos/… not ~/.stubbe/….
      sharedScripts = "/etc/nixos/dotfiles/src/_shared/scripts";
    in
    {
      security.polkit.enable = true;

      # Polkit rule files are parsed in lexical order; the file names match
      # what the non-NixOS activation scripts install under /etc/polkit-1/rules.d/.
      environment.etc."polkit-1/rules.d/49-openconnect.rules".text = homeLib.substituteFile {
        file = self + "/src/polkit/49-openconnect.rules";
        vars = {
          USERNAME = username;
          HOME = home;
        };
      };

      environment.etc."polkit-1/rules.d/50-power-profile-fix.rules".text = homeLib.substituteFile {
        file = self + "/src/polkit/50-power-profile-fix.rules";
        vars = {
          USERNAME = username;
          HELPER_PATH = "${sharedScripts}/power.profile.helper.sh";
        };
      };
    };
}
