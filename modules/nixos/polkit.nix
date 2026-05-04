{ self, ... }:
{
  flake.modules.nixos.polkit =
    { lib, ... }:
    let
      username = "stubbe";
      home = "/home/${username}";
      sharedScripts = "${home}/.stubbe/src/_shared/scripts";

      substitute =
        substitutions: file:
        let
          replacePairs = lib.mapAttrsToList (k: v: { from = k; to = v; }) substitutions;
          template = builtins.readFile file;
        in
        builtins.replaceStrings
          (map (p: p.from) replacePairs)
          (map (p: p.to) replacePairs)
          template;

      vpnRule = substitute {
        "@USERNAME@" = username;
        "@HOME@" = home;
      } (self + "/src/polkit/49-openconnect.rules");

      powerProfileRule = substitute {
        "@USERNAME@" = username;
        "@HELPER_PATH@" = "${sharedScripts}/power.profile.helper.sh";
      } (self + "/src/polkit/50-power-profile-fix.rules");
    in
    {
      security.polkit.enable = true;

      # Polkit rule files are parsed in lexical order; the file names match
      # what the non-NixOS activation scripts install under /etc/polkit-1/rules.d/.
      environment.etc."polkit-1/rules.d/49-openconnect.rules".text = vpnRule;
      environment.etc."polkit-1/rules.d/50-power-profile-fix.rules".text = powerProfileRule;
    };
}
