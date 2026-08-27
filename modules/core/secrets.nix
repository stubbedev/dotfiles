# sops-nix for both classes. Encrypted material lives under secrets/, keyed to
# per-machine age recipients in .sops.yaml.
#
# There is deliberately no `defaultSopsFile` on the home-manager side: every
# `sops.secrets.<name>` spells out its own backing file via `pkgs.stubbe.secret`,
# so reading a module tells you exactly which ciphertext feeds which path, with
# no implicit fallback to guess about.
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

      # Decrypt at activation using the user's SSH ed25519 key; sops-nix
      # converts it to an age identity in memory, so no on-disk age key is
      # needed.
      sops.age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

      # The sops CLI does not read SSH keys directly — it expects an age
      # identity at ~/.config/sops/age/keys.txt. Materialise it from the SSH key
      # so `sops secrets/<file>` works on a fresh machine with no extra setup.
      stubbe.setup.sopsAgeKey.script = ''
        ageKeyFile="$HOME/.config/sops/age/keys.txt"
        sshKey="$HOME/.ssh/id_ed25519"
        if [ -f "$sshKey" ] && { [ ! -f "$ageKeyFile" ] || [ "$sshKey" -nt "$ageKeyFile" ]; }; then
          mkdir -p "$(dirname "$ageKeyFile")"
          ${lib.getExe pkgs.ssh-to-age} -private-key -i "$sshKey" -o "$ageKeyFile"
          chmod 600 "$ageKeyFile"
        fi
      '';

      # Tools for editing/encrypting/managing secrets:
      #   sops secrets/foo.yaml               # edit existing
      #   sops updatekeys secrets/foo.yaml    # re-wrap after a .sops.yaml change
      #   ssh-to-age < ~/.ssh/id_ed25519.pub  # derive the age recipient pubkey
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

      # No defaultSopsFile here either: every secret (including the NixOS-class
      # github-token in modules/nix.nix) names its own backing file via
      # pkgs.stubbe.secret.

      # Decrypt at boot from the host's SSH ed25519 key; sops-nix derives an age
      # identity from it in memory, so no /var/lib age key needs provisioning.
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
}
