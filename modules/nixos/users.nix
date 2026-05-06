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
        ];
      };
    };
}
