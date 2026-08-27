_: {
  flake.modules.nixos.polkit =
    { config, pkgs, ... }:
    let
      username = config.host.primaryUser;
      # NixOS with useUserPackages places the home-manager profile at
      # /etc/profiles/per-user/<user>; this mirrors config.stubbe.paths.nixBin's
      # parent, which the standalone-HM activation in modules/vpn.nix uses.
      profileDir = "/etc/profiles/per-user/${username}";
    in
    {
      security.polkit.enable = true;

      # Rule files are parsed in lexical order; the names match what the
      # non-NixOS activations install under /etc/polkit-1/rules.d/.
      environment.etc = {
        "polkit-1/rules.d/49-openconnect.rules".source =
          pkgs.stubbe.render "src/polkit/49-openconnect.rules"
            {
              USERNAME = username;
              PROFILE_DIR = profileDir;
            };

        "polkit-1/rules.d/52-power-management.rules".source =
          pkgs.stubbe.render "src/polkit/52-power-management.rules"
            {
              USERNAME = username;
            };
      };
    };
}
