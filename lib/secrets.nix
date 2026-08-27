# sops secret declarations rooted at <repo>/secrets/.
{ self }:
{
  # Declare a binary-mode sops secret that lives at <repo>/secrets/<name>
  # and decrypts to `path` at activation. Returns the value for
  # sops.secrets.<key>; the caller picks the attrset key.
  #
  #   sops.secrets.foo = homeLib.mkBinarySecret {
  #     name = "foo";   # secrets/foo
  #     path = "${config.home.homeDirectory}/.config/foo";
  #   };
  mkBinarySecret =
    { name, path }:
    {
      sopsFile = self + "/secrets/${name}";
      format = "binary";
      inherit path;
    };
}
