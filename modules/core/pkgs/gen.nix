# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Config-file generators: wrappers over pkgs.formats, a writer for the DSL
# nixpkgs has none for, and the text variants for content that gets
# concatenated rather than written straight out.
_: {
  stubbe.pkgsLib = {
    gen =
      {
        final,
        ...
      }:
      let
        inherit (final) lib;

        viaFormat = fmt: name: fmt.generate name;
        viaText =
          render: name: value:
          final.writeText name (render value);

        # Text, not a file: for content that lands inline in a setup script or
        # gets concatenated after a stubbe.managedBy marker.
        iniText = lib.generators.toINI { };
        # systemd/udev units: repeated keys are lists (After = a; After = b),
        # and bare true/false render as 1/0, which systemd accepts.
        unitText = lib.generators.toINI { listsAsDuplicateKeys = true; };
      in
      {
        inherit iniText unitText;
        json = viaFormat (final.formats.json { });
        toml = viaFormat (final.formats.toml { });
        yaml = viaFormat (final.formats.yaml { });
        ini = viaText iniText;
        systemd = viaText unitText;
      };
  };
}
