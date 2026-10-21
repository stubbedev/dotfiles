# Branch of the stubbe.lib trunk (see ../lib.nix).
# Where repositories live, relative to $HOME: NixOS creates these directories
# and direnv trusts every .envrc beneath them.
_: {
  stubbe.lib.repoDirs = [
    "git/work"
    "git/private"
  ];
}
