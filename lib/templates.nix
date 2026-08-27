# Eval-time text helpers over files in the repo tree.
{ lib }:
{
  # Read `file` and replace each @KEY@ marker with the corresponding
  # value from `vars`. Used for files whose content depends on the
  # user's home directory / username and which are baked at eval time.
  substituteFile =
    { file, vars }:
    builtins.replaceStrings (map (k: "@${k}@") (lib.attrNames vars)) (lib.attrValues vars) (
      builtins.readFile file
    );
}
