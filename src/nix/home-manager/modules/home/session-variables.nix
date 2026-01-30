{ ... }:
{
  flake.modules.homeManager.sessionVariables = { config, lib, pkgs, ... }:
    {
      home.sessionVariables = {
        # Nix configuration
        NIXPKGS_ALLOW_UNFREE = "1";
        NIXPKGS_ALLOW_INSECURE = "1";
        NIXOS_OZONE_WL = "1";

        # Editor and display
        EDITOR = lib.getExe pkgs.neovim;
        # DISPLAY = ":0";

        # Desktop entries (Flatpak + Nix)
        XDG_DATA_DIRS = lib.mkForce
          "${config.home.homeDirectory}/.local/share/flatpak/exports/share:${config.home.homeDirectory}/.nix-profile/share:/nix/var/nix/profiles/default/share:/var/lib/flatpak/exports/share:/usr/share/ubuntu:/usr/local/share:/usr/share:/var/lib/snapd/desktop:$XDG_DATA_DIRS";

        # Paging and documentation
        MANPAGER = "sh -c 'col -bx | bat -l man -p'";
        MANROFFOPT = "-c";
        PAGER = "${pkgs.more}/bin/more";

        # Go configuration
        GOROOT = "${config.home.homeDirectory}/.go";
        GOPATH = "${config.home.homeDirectory}/go";

        # Theme and custom variables
        DEPLOYER_REMOTE_USER = "abs";
      };
    };
}
