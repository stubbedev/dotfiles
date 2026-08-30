_: {
  flake.modules.nixos.users =
    { config, ... }:
    {
      users.users.${config.host.primaryUser} = {
        isNormalUser = true;
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
