_: {
  flake.modules.nixos.networking =
    { lib, ... }:
    {
      networking.networkmanager.enable = true;
      networking.firewall.enable = true;
      # Stealth: drop ICMP echo from non-LAN. Breaks ping diagnostics
      # but stops trivial host enumeration.
      networking.firewall.allowPing = false;

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
          # mkDefault so the live ISO can override to
          # "prohibit-password" — root login over SSH is the only way
          # to remote-debug a stuck install.
          PermitRootLogin = lib.mkDefault "no";
        };
      };

      # NM-wait-online blocks boot until any connection is up; on a
      # desktop with offline-friendly services this just adds 20s to
      # every boot. Disable; services that genuinely need network use
      # NetworkManager-online.target instead.
      systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
    };
}
