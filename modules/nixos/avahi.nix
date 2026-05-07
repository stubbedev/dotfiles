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
