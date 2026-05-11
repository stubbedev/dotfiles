_: {
  # Pre-create the personal directory layout on first boot. Without
  # this, `cd ~/git/work` after a fresh install fails until manually
  # mkdir'd. tmpfiles re-runs each boot but `d` is idempotent and
  # never touches existing contents.
  flake.modules.nixos.user-dirs =
    { config, ... }:
    let
      user = config.host.primaryUser;
      home = config.users.users.${user}.home;
      group = config.users.users.${user}.group;
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
