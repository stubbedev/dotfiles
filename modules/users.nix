_: {
  flake.modules.nixos.users =
    { config, ... }:
    {
      users.users.${config.host.primaryUser} = {
        isNormalUser = true;
        # Plain list (not lib.mkDefault) so other modules that contribute
        # groups (e.g. docker.nix appends "docker") merge into one list.
        # mkDefault on a list option gets dropped entirely when a normal-
        # priority definition appears, which would lose the base groups.
        extraGroups = [
          "wheel"
          "video"
          "audio"
          "networkmanager"
          "i2c"
          "dialout"
        ];
      };
    };

  # Pre-create the personal directory layout on first boot; without it
  # `cd ~/git/work` after a fresh install fails until manually mkdir'd.
  flake.modules.nixos.userDirs =
    { config, ... }:
    let
      user = config.host.primaryUser;
      inherit (config.users.users.${user}) home group;
    in
    {
      systemd.tmpfiles.rules = [
        "d ${home}/git         0755 ${user} ${group} - -"
        "d ${home}/git/work    0755 ${user} ${group} - -"
        "d ${home}/git/private 0755 ${user} ${group} - -"
        "d ${home}/docs        0755 ${user} ${group} - -"
      ];
    };
}
