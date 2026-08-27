# stubbe — standalone home-manager on a non-NixOS distro (Ubuntu today).
#
# Composing a host is just "take every aspect": each file under modules/
# registers itself under `flake.modules.homeManager.<aspect>`, so there is no
# import list here to keep in sync. Aspects gate themselves on `features.*`
# and on `host.platform`, which defaults to "linux" — meaning the privileged
# half of each aspect runs as a sudo-prompted activation rather than being
# owned by a NixOS module.
{ config, ... }:
{
  configurations.homeManager.stubbe = {
    system = "x86_64-linux";
    module.imports = builtins.attrValues config.flake.modules.homeManager;
  };
}
