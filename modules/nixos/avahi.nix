_: {
  flake.modules.nixos.avahi =
    { ... }:
    {
      # mDNS / DNS-SD: advertise this machine to printers / Chromecasts /
      # dev boxes on the LAN, and keep service discovery working.
      #
      # nssmdns4 is intentionally OFF: it hooks `mdns4_minimal [NOTFOUND=return]`
      # into nsswitch ahead of `resolve`, which hijacks every `*.local` lookup to
      # multicast mDNS and returns before systemd-resolved is consulted. srv
      # routes its local domains (incl. `*.local`) through dnsmasq via a
      # systemd-resolved drop-in, so with nss-mdns in front, `grafana.local` etc.
      # never reach dnsmasq and fail to resolve. Turning it off lets `resolve`
      # answer `.local` from dnsmasq.
      # Trade-off: glibc no longer resolves *other* hosts' `.local` names via
      # mDNS (e.g. `ssh printer.local`); the avahi daemon still advertises this
      # host and powers DNS-SD service discovery.
      services.avahi = {
        enable = true;
        nssmdns4 = false;
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
