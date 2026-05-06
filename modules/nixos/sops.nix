{ inputs, self, ... }:
{
  flake.modules.nixos.sops =
    { lib, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      # System secrets live in secrets/system.yaml (re-keyed under .sops.yaml
      # to the host's age recipient). Per-user secrets continue to flow
      # through the HM module at modules/sops.nix on a per-secret basis.
      sops.defaultSopsFile = lib.mkDefault (self + "/secrets/system.yaml");

      # Decrypt at boot using the host's SSH ed25519 key. sops-nix derives
      # an age identity from it in-memory; no separate /var/lib age key
      # needs to be provisioned by hand.
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
}
