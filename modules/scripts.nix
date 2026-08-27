# The `bin/` CLI: every tracked script under bin/ becomes a Nix bin on PATH.
#
# Only the *generic* tools live here. App-specific scripts belong to their
# aspect (mail helpers in modules/mail.nix, the wayle launcher in
# modules/wayle.nix, brightness in modules/hyprland.nix, …) so that adding a
# script to a feature never means editing a second file.
{ self, ... }:
{
  flake.modules.homeManager.scripts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Auto-discovered: the bin name IS the filename, so a new script is on
      # PATH the moment it is committed. Three exclusions:
      #   stb-install        pre-Nix bootstrap; runs from the checkout
      #   stb-install-nixos  ISO-only; modules/installer.nix reads it directly
      #   hm, nixos-iso      need @…@ substitution, so they are listed below
      excluded = [
        "stb-install"
        "hm"
        "nixos-iso"
      ];
      autoNames = lib.attrNames (
        lib.filterAttrs (name: type: type == "regular" && !(builtins.elem name excluded)) (
          builtins.readDir (self + "/bin")
        )
      );
      autoBins = map (
        name:
        pkgs.stubbe.scriptBin {
          inherit name;
          source = "bin/${name}";
        }
      ) autoNames;

      # hm and nixos-iso are templated against absolute store paths for
      # sops/age/ssh-to-age/xilo, so the wrapper never depends on whatever
      # happens to be on PATH at invocation time.
      hm = pkgs.stubbe.scriptBin {
        name = "hm";
        source = "bin/hm";
        vars = {
          FLAKE_DIR = config.stubbe.paths.dotfiles;
          SOPS = lib.getExe pkgs.sops;
          AGE = lib.getExe pkgs.age;
          SSH_TO_AGE = lib.getExe pkgs.ssh-to-age;
          # getExe' rather than getExe: do not assume a flake package carries
          # meta.mainProgram.
          XILO = lib.getExe' pkgs.xilo "xilo";
        };
      };

      nixosIso = pkgs.stubbe.scriptBin {
        name = "nixos-iso";
        source = "bin/nixos-iso";
        vars.FLAKE_DIR = config.stubbe.paths.dotfiles;
      };
    in
    {
      home.packages = [
        hm
        nixosIso
        # `hm` shells out to nh for build/activate/gc, so nh ships wherever hm
        # does — which is every host.
        pkgs.nh
      ]
      # The rest are tmux/fzf launchers: desktop-only.
      ++ lib.optionals config.features.desktop autoBins;
    };
}
