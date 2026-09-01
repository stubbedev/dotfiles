# compinit indexes a completion file only by its `#compdef` first line, and a
# missing tag fails silently: the file ships, the widget never binds. Reads the
# zcompdump the .zshrc actually loads (it is a reference of that file, so the
# sandbox has it) and asserts our own completers are in it.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.zsh-completions =
        pkgs.runCommand "check-zsh-completions"
          {
            zshrc = self.homeConfigurations.stubbe.config.home.file."./.zshrc".source;
          }
          ''
            set -euo pipefail

            dump=$(grep -o '/nix/store/[^ ]*-stubbe-zcompdump/zcompdump' "$zshrc" | head -1)
            [ -n "$dump" ] || { echo ".zshrc loads no zcompdump" >&2; exit 1; }

            for cmd in hm denv; do
              grep -q "'$cmd' '_$cmd'" "$dump" ||
                { echo "compinit did not index _$cmd — missing '#compdef $cmd' first line?" >&2; exit 1; }
            done

            touch "$out"
          '';
    };
}
