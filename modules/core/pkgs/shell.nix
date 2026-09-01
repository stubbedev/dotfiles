# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Script writers. All of them syntax-check and shellcheck what they build.
let
  shellFile =
    {
      final,
      lib,
      stubbe,
      ...
    }:
    {
      name,
      text,
      bin ? false,
    }:
    final.writeTextFile {
      inherit name;
      executable = true;
      destination = lib.optionalString bin "/bin/${name}";
      meta.mainProgram = name;
      text = ''
        #!${final.runtimeShell}
        ${text}'';
      checkPhase = ''
        ${final.stdenv.shellDryRun} "$target"
        ${lib.getExe final.shellcheck} -S warning "$target"
      '';
    };
in
{
  stubbe.pkgsLib = {
    # -S warning, not the default style severity, which fails builds on
    # cosmetic findings.
    bashApp =
      { final, lib, ... }:
      {
        name,
        text,
        runtimeInputs ? [ ],
      }:
      final.writeShellApplication {
        inherit name text runtimeInputs;
        checkPhase = ''
          runHook preCheck
          ${final.stdenv.shellDryRun} "$target"
          ${lib.getExe final.shellcheck} -S warning "$target"
          runHook postCheck
        '';
      };

    # Drop-in replacements for writeShellScript/writeShellScriptBin that add
    # bashApp's checks. Separate from bashApp because writeShellApplication
    # always prepends `set -euo pipefail`, which rewrites the control flow of
    # scripts not written for it; these keep plain semantics and only add the
    # syntax check and shellcheck.

    zshApp =
      { final, lib, ... }:
      { name, text }:
      final.writeTextFile {
        inherit name;
        executable = true;
        destination = "/bin/${name}";
        text = ''
          #!${lib.getExe final.zsh}
          ${text}'';
        checkPhase = ''
          ${lib.getExe final.zsh} -n "$target"
        '';
        meta.mainProgram = name;
      };

    # Drop-in replacements for writeShellScript/writeShellScriptBin that add
    # bashApp's checks. Separate from bashApp because writeShellApplication
    # always prepends `set -euo pipefail`, which rewrites the control flow of
    # scripts not written for it; these keep plain semantics and only add the
    # syntax check and shellcheck.
    shellScript =
      args: name: text:
      shellFile args { inherit name text; };

    shellScriptBin =
      args: name: text:
      shellFile args {
        inherit name text;
        bin = true;
      };
  };
}
