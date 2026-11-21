{ config, ... }:
{
  configurations.nixos.desktop = {
    system = "x86_64-linux";
    module = {
      imports = builtins.attrValues config.flake.modules.nixos;

      networking.hostName = "stubbe-nixos";
      system.stateVersion = "26.05";

      host = {
        installed = true;
        graphicsNvidia = true;

        # The phone is the only aarch64 machine, and it cannot compile its own
        # closure in any useful time. Emulating aarch64 here registers it with
        # binfmt_misc and adds it to the daemon's extra-platforms, which is what
        # lets the phone build remotely (modules/hosts/stubbe-phone.nix) and
        # what makes this host push the phone's closure to the cache after a
        # switch (modules/nix.nix).
        emulatedSystems = [ "aarch64-linux" ];
      };
    };
  };
}
