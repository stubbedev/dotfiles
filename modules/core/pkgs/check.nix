# Branch of the pkgs.stubbe helper tree (see ./default.nix). Every flake
# check runs through here so its script is bounded by `timeout`: a check
# that starts something interactive used to wedge `nix flake check` forever
# (the tmux-session check once drove an fzf picker inside its sandbox).
# Through this runner a wedged check fails instead.
_: {
  stubbe.pkgsLib.check =
    { final, lib, ... }:
    {
      name,
      text,
      timeout ? 600,
      nativeBuildInputs ? [ ],
      env ? { },
    }:
    final.runCommand "check-${name}" ({ inherit nativeBuildInputs; } // env) ''
      ${final.coreutils}/bin/timeout ${toString timeout} \
        ${final.bash}/bin/bash -c ${lib.escapeShellArg text}
    '';
}
