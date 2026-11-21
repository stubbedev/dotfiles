{ inputs, ... }:
{
  flake.modules.homeManager.secrets =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.sops-nix.homeManagerModules.sops ];

      sops.age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

      home.sessionVariables.SOPS_AGE_KEY_CMD = lib.escapeShellArgs [
        (lib.getExe pkgs.ssh-to-age)
        "-private-key"
        "-i"
        (lib.head config.sops.age.sshKeyPaths)
      ];

      home.packages = with pkgs; [
        sops
        ssh-to-age
        age
      ];
    };

  flake.modules.nixos.secrets = {
    imports = [ inputs.sops-nix.nixosModules.sops ];
  };
}
