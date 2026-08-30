_: {
  flake.modules.homeManager.mutable =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      liveRoot = "${config.stubbe.paths.dotfiles}/src";

      sourceOf = m: if m.src != null then "${liveRoot}/${m.src}" else "${m.source}";
      targetOf = m: "${config.home.homeDirectory}/${m.target}";

      renderEntry =
        m:
        let
          src = lib.escapeShellArg (sourceOf m);
          dst = lib.escapeShellArg (targetOf m);
        in
        {
          link = ''
            mkdir -p "$(dirname ${dst})"
            rm -rf ${dst}
            ln -s ${src} ${dst}
          '';

          copy = ''
            mkdir -p "$(dirname ${dst})"
            rm -rf ${dst}
            install -m ${m.mode} ${src} ${dst}
          '';
        }
        .${m.method};

      entries = lib.attrValues config.stubbe.mutable;
    in
    {
      options.stubbe.mutable = lib.mkOption {
        description = "Files installed writable rather than as read-only store symlinks, keyed by path relative to $HOME.";
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options = {
                target = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  defaultText = "the attribute name";
                  description = "Path relative to $HOME. Defaults to the attribute name.";
                };

                method = lib.mkOption {
                  type = lib.types.enum [
                    "link"
                    "copy"
                  ];
                  default = "link";
                  description = "link: symlink the live checkout. copy: re-assert our content each switch.";
                };

                src = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Path under `<stubbe.paths.dotfiles>/src`, resolved at activation time so checkout edits are live.";
                };

                source = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "A store path to install instead of a checkout path. Mutually exclusive with `src`.";
                };

                text = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  description = "Content generated in Nix; shorthand for `source = pkgs.writeText …`.";
                };

                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "0644";
                  description = "File mode for `copy`.";
                };
              };

              config.source = lib.mkIf (config.text != null) (
                lib.mkDefault (pkgs.writeText (lib.replaceStrings [ "/" ] [ "-" ] name) config.text)
              );
            }
          )
        );
      };

      config = {
        assertions = lib.concatMap (m: [
          {
            assertion = (m.src != null) != (m.source != null);
            message = "stubbe.mutable.\"${m.target}\": set exactly one of `src` (live checkout) or `source`/`text` (generated).";
          }
          {
            assertion = m.method != "link" || m.src != null;
            message = "stubbe.mutable.\"${m.target}\": method \"link\" needs `src` — a store path cannot be made writable.";
          }
        ]) entries;

        home.activation.mutableFiles = lib.mkIf (entries != [ ]) (
          lib.hm.dag.entryAfter [ "linkGeneration" ] (
            lib.concatMapStringsSep "\n" renderEntry (lib.sort (a: b: a.target < b.target) entries)
          )
        );
      };
    };
}
