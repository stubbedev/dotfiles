# Syntax highlighting daemon for zsh (replaces fast-syntax-highlighting).
# The shell-side hook script is generated at switch time by the
# setup-zsh-patina activation (modules/activation/_non-privileged/) and
# sourced from ~/.cache — but that script never starts the daemon (the
# side effect lives in `zsh-patina activate`), so after a reboot
# highlighting would silently do nothing. This service owns the daemon
# lifecycle instead: started at login, restarted on switch when the
# ExecStart store path changes — daemon and script stay version-synced
# because both regenerate from the same binary on switch.
_: {
  flake.modules.homeManager.zshPatina =
    { pkgs, ... }:
    {
      systemd.user.services.zsh-patina = {
        Unit = {
          Description = "zsh-patina syntax highlighting daemon";
        };
        Service = {
          ExecStart = "${pkgs.zsh-patina}/bin/zsh-patina start --no-daemon";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };
}
