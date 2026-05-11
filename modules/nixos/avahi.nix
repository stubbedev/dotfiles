_: {
  flake.modules.nixos.avahi =
    { ... }:
    {
      # mDNS / DNS-SD: resolve `*.local` hostnames, advertise this
      # machine to printers / Chromecasts / dev boxes on the LAN.
      # nssmdns4 hooks avahi into glibc's name resolution so plain
      # `ssh foo.local` works without nss tweaks.
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        # Restrict to real LAN NICs. Without this, avahi advertises on
        # docker0 / br-* / veth* too, which collides the hostname with
        # itself across bridges (stubbe-nixos-2, -3, ...) and leaks the
        # host name into container networks.
        allowInterfaces = [
          "enp4s0"
          "wlp3s0"
        ];
        publish = {
          enable = true;
          addresses = true;
          domain = true;
          hinfo = true;
          userServices = true;
          workstation = true;
        };
      };
    };
}
