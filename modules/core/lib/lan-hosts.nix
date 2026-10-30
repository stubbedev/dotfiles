# Branch of the stubbe.lib trunk (see ../lib.nix).
# The LAN catalogue: every machine the others reach over ssh, keyed by the
# mDNS name it publishes, valued by the user to log in as. `host.mdnsName`
# decides which of these names a machine advertises (modules/network.nix
# feeds it to avahi), and the ssh client config is generated from the same
# list, so a machine cannot be advertised under one name and reached under
# another.
{
  stubbe.lib.lanHosts = {
    laptop = "stubbe";
    desktop = "stubbe";
  };
}
