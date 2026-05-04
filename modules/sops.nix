{ inputs, self, ... }:
{
  flake.modules.homeManager.sops =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.sops-nix.homeManagerModules.sops ];

      # No defaultSopsFile by design — each `sops.secrets.<name>` declaration
      # spells out its own `sopsFile = self + "/secrets/<file>.yaml"`. Reading
      # the module then tells you exactly which encrypted file backs which
      # secret, no implicit fallback to guess about.

      # Decrypt at activation using the user's SSH ed25519 key. sops-nix
      # converts it to an age identity in-memory; no on-disk age key needed.
      sops.age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

      # The sops CLI doesn't read SSH keys directly — it expects an age
      # identity at ~/.config/sops/age/keys.txt. Materialise it from the
      # SSH key on activation so `sops <encrypted>.yaml` works without any
      # extra setup on a fresh machine.
      home.activation.sopsAgeKeyFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ageKeyFile="$HOME/.config/sops/age/keys.txt"
        sshKey="$HOME/.ssh/id_ed25519"
        if [ -f "$sshKey" ] && { [ ! -f "$ageKeyFile" ] || [ "$sshKey" -nt "$ageKeyFile" ]; }; then
          mkdir -p "$(dirname "$ageKeyFile")"
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i "$sshKey" -o "$ageKeyFile"
          chmod 600 "$ageKeyFile"
        fi
      '';

      # Tools for editing/encrypting/managing secrets:
      #   sops secrets/intelephense.yaml          # edit existing
      #   sops updatekeys secrets/foo.yaml        # re-wrap after .sops.yaml change
      #   ssh-to-age < ~/.ssh/id_ed25519.pub      # derive age recipient pubkey
      home.packages = with pkgs; [
        sops
        ssh-to-age
        age
      ];
    };
}
