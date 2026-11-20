{ inputs, ... }:
{
  flake.modules.homeManager.secrets =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      onAndroid = config.host.platform == "android";
    in
    {
      imports = [ inputs.sops-nix.homeManagerModules.sops ];

      sops.age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

      sops.defaultSecretsMountPoint = lib.mkIf onAndroid "${config.xdg.stateHome}/sops-nix/secrets.d";

      home.activation.sops-nix = lib.mkIf onAndroid (
        lib.mkForce (
          lib.hm.dag.entryAfter [ "writeBoundary" ] (
            lib.escapeShellArgs config.systemd.user.services.sops-nix.Service.ExecStart
          )
        )
      );

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
