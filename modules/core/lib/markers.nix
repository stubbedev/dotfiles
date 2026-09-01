# Branch of the stubbe.lib trunk (see ../lib.nix).
# The marker every file we write into someone else's config directory carries,
# so a later reader (or a cleanup pass) can tell our lines from theirs.
_: {
  stubbe.lib.managedBy = name: "# managed-by: stubbe ${name}\n";
}
