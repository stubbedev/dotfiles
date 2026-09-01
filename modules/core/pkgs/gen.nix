# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Config-file generators: wrappers over pkgs.formats, writers for the two DSLs
# nixpkgs has none for, and the text variants for content that gets
# concatenated rather than written straight out.
_: {
  stubbe.pkgsLib = {
    gen =
      {
        final,
        lib,
        stubbe,
        ...
      }:
      let
        inherit (final) lib;

        fileNameOf = relPath: lib.replaceStrings [ "/" ] [ "-" ] relPath;

        # hyprlang: bare `key = value` lines, nested `section { }` blocks, and
        # repeated keys for list values (bind = ..., bind = ...).
        toHyprlang =
          let
            atom =
              v:
              if lib.isBool v then
                lib.boolToString v
              else if lib.isList v then
                lib.concatMapStringsSep "," atom v
              else
                toString v;
            render =
              indent: attrs:
              lib.concatStrings (
                lib.mapAttrsToList (
                  name: value:
                  if value == null then
                    ""
                  else if lib.isAttrs value then
                    "${indent}${name} {\n${render "  ${indent}" value}${indent}}\n"
                  else if lib.isList value then
                    lib.concatMapStrings (v: "${indent}${name} = ${atom v}\n") value
                  else
                    "${indent}${name} = ${atom value}\n"
                ) attrs
              );
          in
          render "";

        # rasi: `@import`/`@theme` directives plus `selector { prop: value; }`
        # blocks. Strings are quoted unless they are a rasi reference (@name), a
        # colour literal (#rrggbb), or wrapped in stubbe.rasiLiteral.
        toRasi =
          {
            imports ? [ ],
            theme ? null,
            sections ? { },
          }:
          let
            value =
              v:
              if lib.isAttrs v && v ? __rasi then
                v.__rasi
              else if lib.isBool v then
                lib.boolToString v
              else if lib.isList v then
                "[ ${lib.concatMapStringsSep ", " value v} ]"
              else if lib.isString v && (lib.hasPrefix "@" v || lib.hasPrefix "#" v) then
                v
              else if lib.isString v then
                "\"${v}\""
              else
                toString v;
            block =
              selector: props:
              "${selector} {\n${lib.concatStrings (lib.mapAttrsToList (k: v: "  ${k}: ${value v};\n") props)}}\n";
          in
          lib.concatStrings (
            map (i: "@import \"${i}\"\n") imports
            ++ [ (lib.optionalString (imports != [ ]) "\n") ]
            ++ lib.mapAttrsToList block sections
            ++ lib.optional (theme != null) "@theme \"${theme}\"\n"
          );

        viaFormat = fmt: name: fmt.generate name;
        viaText =
          render: name: value:
          final.writeText name (render value);
      in
      {
        inherit fileNameOf;

        json = viaFormat (final.formats.json { });
        toml = viaFormat (final.formats.toml { });
        yaml = viaFormat (final.formats.yaml { });
        ini = viaText (lib.generators.toINI { });
        # nixpkgs has no writer for these two: hyprlang lives in home-manager's
        # module lib and rasi is private to its rofi module, so neither is
        # reachable from an overlay.
        hyprlang = viaText toHyprlang;
        rasi = viaText toRasi;

        # Text, not a file: for content that lands inline in a setup script or
        # gets concatenated after a stubbe.managedBy marker.
        iniText = lib.generators.toINI { };
        # The systemd/udev dialect, where a repeated key is a list rather than
        # an override.
        unitText = lib.generators.toINI { listsAsDuplicateKeys = true; };
      };

    # xdg.configFile shape: { "<path>" = <value>; } -> { "<path>".source = …; },
    # so a module names each config file once.
    conf =
      { lib, stubbe, ... }:
      lib.mapAttrs
        (_: writer: lib.mapAttrs (path: value: { source = writer (stubbe.gen.fileNameOf path) value; }))
        (
          removeAttrs stubbe.gen [
            "fileNameOf"
            "iniText"
            "unitText"
          ]
        );

    # Escape hatch for rasi values that are neither string nor number: sizes,
    # insets, and anything else rasi wants unquoted.
    rasiLiteral = _: raw: { __rasi = raw; };
  };
}
