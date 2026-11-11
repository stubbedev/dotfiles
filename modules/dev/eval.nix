{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      evalGuard =
        name: packages:
        pkgs.stubbe.check {
          inherit name;
          env.toplevels = lib.concatMapStringsSep " " (
            package: builtins.unsafeDiscardStringContext package.drvPath
          ) packages;
          text = ''
            echo "evaluated: $toplevels" > "$out"
          '';
        };
    in
    {
      checks = {
        # `nix flake check` evaluates every nixosConfigurations toplevel
        # natively, but never touches homeConfigurations, so the standalone
        # host needs its own eval guard.
        eval-hm-stubbe = evalGuard "eval-hm-stubbe" [ self.homeConfigurations.stubbe.activationPackage ];
        eval-nixos = evalGuard "eval-nixos" (
          map (host: host.config.system.build.toplevel) (lib.attrValues self.nixosConfigurations)
        );
      }
      # nixOnDroidConfigurations is an output nix does not know, so it is
      # left out of `nix flake check` entirely. Its home-manager half
      # evaluates off the phone (only user.uid/gid need an aarch64 builder),
      # so a broken module set on Android fails here rather than at the next
      # switch.
      // lib.mapAttrs' (
        name: host:
        lib.nameValuePair "eval-nix-on-droid-${name}" (
          evalGuard "eval-nix-on-droid-${name}" [ host.config.home-manager.config.home.activationPackage ]
        )
      ) self.nixOnDroidConfigurations;
    };
}
