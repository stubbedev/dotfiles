# Map src/ trees into home-manager xdg entries.
{
  lib,
  self,
}:
rec {

  # Map a path under src/<path> to an entry in xdg.configFile. `extra`
  # is merged into the file attrset (e.g. onChange hooks). `target` lets
  # the path under ~/.config differ from the source path under src/, for
  # tools that hardcode a flat config path (e.g. cship reads ~/.config/cship.toml).
  xdgSource =
    path:
    {
      target ? path,
      ...
    }@extra:
    {
      "${target}" = {
        source = self + "/src/${path}";
        force = true;
      }
      // (removeAttrs extra [ "target" ]);
    };

  # Bulk variant: map a list of paths with no extra args.
  xdgSources = paths: lib.foldl' (acc: p: acc // xdgSource p { }) { } paths;

  # Read raw text of a file under src/ at evaluation time. Pair with
  # builtins.fromJSON / fromTOML when you need parsed data.
  xdgContent = path: builtins.readFile (self + "/src/${path}");
}
