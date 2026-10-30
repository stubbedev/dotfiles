# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Script writers. All of them syntax-check and shellcheck what they build.
let
  # -S warning, not the default style severity, which fails builds on
  # cosmetic findings.
  lint =
    { final, lib, ... }:
    ''
      ${final.stdenv.shellDryRun} "$target"
      ${lib.getExe final.shellcheck} -S warning "$target"
    '';

  shellFile =
    {
      final,
      lib,
      ...
    }@args:
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
      checkPhase = lint args;
    };
in
{
  stubbe.pkgsLib = {
    bashApp =
      { final, ... }@args:
      {
        name,
        text,
        runtimeInputs ? [ ],
      }:
      final.writeShellApplication {
        inherit name text runtimeInputs;
        checkPhase = ''
          runHook preCheck
          ${lint args}
          runHook postCheck
        '';
      };

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
