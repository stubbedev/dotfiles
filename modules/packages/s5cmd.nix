_: {
  # s5cmd (github.com/peak/s5cmd) — fast parallel S3 CLI (Go), used to talk
  # to the local Garage instance. Installed both home-manager- and
  # system-wide so it's on PATH for the primary user and any non-HM login
  # shell on the box.
  flake.modules.nixos.packagesS5cmd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.s5cmd ];
    };

  flake.modules.homeManager.packagesS5cmd =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.s5cmd ];
    };
}
