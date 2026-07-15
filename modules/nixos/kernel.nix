_: {
  flake.modules.nixos.kernel = _: {
    # NixOS counterpart of modules/activation/_privileged/setup-inotify-limits.nix.
    # The 65536 default is exhausted by webpack-dev-server + octane --watch over
    # large node_modules trees → ENOSPC "file watchers reached".
    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 512;
    };
  };
}
