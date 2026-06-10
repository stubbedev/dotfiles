_: {
  # Official Vultr CLI (github.com/vultr/vultr-cli), packaged in nixpkgs.
  # Installed both home-manager- and system-wide so it's on PATH for the
  # primary user and any non-HM login shell on the box.
  flake.modules.nixos.packagesVultr =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vultr-cli ];
    };

  flake.modules.homeManager.packagesVultr =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.vultr-cli ];
    };
}
