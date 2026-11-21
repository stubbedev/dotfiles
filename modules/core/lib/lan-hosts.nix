# Branch of the stubbe.lib trunk (see ../lib.nix).
# The LAN catalogue: every machine the others reach over ssh, keyed by the
# srv peer name it announces (its `host.flakeAttr`), with the user to log in
# as and the port its sshd listens on. srv serves each announced peer as
# `<name>.<peerZone>`, and the ssh client config is generated from the same
# list, so a machine cannot be announced under one name and reached under
# another. The phone's sshd runs unprivileged, so it cannot bind below 1024.
# `peerPort` is srv's fixed discovery port (constants.PortPeer upstream).
# `sshdSettings` is the one sshd policy, applied by services.openssh on NixOS
# and rendered into the phone's sshd_config.
{
  stubbe.lib = {
    lanHosts = {
      laptop = {
        user = "stubbe";
        port = 22;
      };
      desktop = {
        user = "stubbe";
        port = 22;
      };
      phone = {
        user = "nix-on-droid";
        port = 8022;
      };
    };
    peerZone = "home.arpa";
    peerPort = 15354;
    sshdSettings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      ClientAliveInterval = 60;
      ClientAliveCountMax = 3;
    };
  };
}
