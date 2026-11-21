# Branch of the stubbe.lib trunk (see ../lib.nix).
# The LAN catalogue: every machine the others reach over ssh, keyed by the
# srv peer name it announces (its `host.flakeAttr`), valued by the user to log
# in as. srv serves each announced peer as `<name>.<peerZone>`, and the ssh
# client config is generated from the same list, so a machine cannot be
# announced under one name and reached under another. `peerPort` is srv's
# fixed discovery port (constants.PortPeer upstream).
{
  stubbe.lib = {
    lanHosts = {
      laptop = "stubbe";
      desktop = "stubbe";
    };
    peerZone = "home.arpa";
    peerPort = 15354;
  };
}
