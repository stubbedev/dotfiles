_: {
  args =
    { homeLib, ... }:
    homeLib.mkInstallPrompt {
      subject = "inotify watch/instance limits";
      body = ''
        Raises fs.inotify.max_user_watches and max_user_instances. The 65536
        default is exhausted by webpack-dev-server + octane --watch over large
        node_modules trees, causing ENOSPC "file watchers reached" errors.
      '';
      actionScript = ''
        ${homeLib.installSystemFile {
          target = "/etc/sysctl.d/60-inotify-limits.conf";
          content = ''
            # managed-by: home-manager inotify-limits
            fs.inotify.max_user_watches = 524288
            fs.inotify.max_user_instances = 512
          '';
        }}

        if command -v sysctl >/dev/null 2>&1; then
          sudo sysctl --system >/dev/null 2>&1 || true
        fi
      '';
    };
}
