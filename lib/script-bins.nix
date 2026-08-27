# Executable script binaries written into config.home.profileDirectory/bin/.
{
  self,
  substituteFile,
  pkgs ? null,
}:
let
  # Guard inside function bodies — callers may import lib.nix without
  # pkgs and only force these when they call the builder.
  requirePkgs = name: if pkgs == null then throw "homeLib.${name}: pkgs is required" else pkgs;
in
{
  # Read a script at <repo-root>/<source>, apply @KEY@ substitutions, and
  # build it as an executable Nix derivation that lands under
  # config.home.profileDirectory/bin/<name>. Preserves the script's own shebang
  # (so zsh stays zsh, bash stays bash). Use this instead of writing
  # things to home.file.".local/bin/x" — keeps scripts on PATH and
  # owned by the Nix profile.
  mkScriptBin =
    {
      name,
      source, # path relative to repo root, e.g. "src/aerc/scripts/x.sh" or "bin/y"
      vars ? { },
    }:
    (requirePkgs "mkScriptBin").writeTextFile {
      inherit name;
      text = substituteFile {
        file = self + "/${source}";
        inherit vars;
      };
      executable = true;
      destination = "/bin/${name}";
    };
}
