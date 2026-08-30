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

      stubbe.setup.sopsAgeKey.script = ''
        ageKeyFile="$HOME/.config/sops/age/keys.txt"
        sshKey="$HOME/.ssh/id_ed25519"
        if [ -f "$sshKey" ] && { [ ! -f "$ageKeyFile" ] || [ "$sshKey" -nt "$ageKeyFile" ]; }; then
          mkdir -p "$(dirname "$ageKeyFile")"
          ${lib.getExe pkgs.ssh-to-age} -private-key -i "$sshKey" -o "$ageKeyFile"
          chmod 600 "$ageKeyFile"
        fi
      '';

      home.packages = with pkgs; [
        sops
        ssh-to-age
        age
      ];
    };

  flake.modules.nixos.secrets =
    { ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
}
