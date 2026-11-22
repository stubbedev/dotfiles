# Branch of the stubbe.lib trunk (see ../lib.nix).
# Substituters and the nixpkgs config every class instantiates pkgs with.
_: {
  stubbe.lib = {
    cache = rec {
      xilo = rec {
        url = "https://xilos.dev";
        cache = "stubbedev/main";
        store = "${url}/c/${cache}";
      };
      # xilo (xilos.dev) first: self-hosted cache is preferred, then
      # upstream and nix-community.
      substituters = [
        xilo.store
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "xilos.dev/stubbedev/main-1:397R6S49v/FSvP+mZ3HlKrVN1KXhgzHIEIHxA/UuG6Y="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # The nix.conf keys every consumer writes: the NixOS daemon, the
      # nix-on-droid /etc/nix/nix.conf and the user-level one on the phone.
      # narinfo-cache-negative-ttl is deliberately NOT here: only the hosts
      # that push to xilo need it, and the phone, which never has a path there,
      # would pay a negative lookup per path on every build.
      settings = {
        inherit substituters trusted-public-keys;

        # At the 1 MiB default the NAR decompressor blocks as soon as the
        # buffer fills and downloads run in lockstep with the writer.
        download-buffer-size = 128 * 1024 * 1024;

        # Without it a build on a phone with no route to xilos.dev hangs on
        # the first reachability probe instead of moving on to cache.nixos.org.
        connect-timeout = 5;
      };
    };

    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "dcraw-9.28.0"
      ];
    };
  };
}
