# Wrapped-package bundling.
{
  lib,
  pkgs ? null,
  gfxName,
  gfxExe,
}:
let
  # Guard inside function bodies — callers may import lib.nix without
  # pkgs and only force these when they call the builder.
  requirePkgs = name: if pkgs == null then throw "homeLib.${name}: pkgs is required" else pkgs;
in
{
  # Wrap a package's binaries with nixGL + makeWrapper, then bundle the
  # result back together with the upstream paths via symlinkJoin. This
  # collapses the gfx-wrap → makeWrapper → symlinkJoin pattern that
  # repeats for chrome / slack / firefox / remmina.
  #
  # exes:           binaries to wrap. The first uses lib.getExe (the
  #                 package's mainProgram); subsequent entries use
  #                 lib.getExe' to look up by name.
  # gfx:            wrap with nixGL. Default true.
  # flags:          --add-flags entries.
  # env:            { K = "v"; } → --set K v.
  # unset:          [ "K" ] → --unset K.
  # prefix:         { K = "v"; } → --prefix K : v.
  # includeUpstream: include the upstream package in the symlinkJoin
  #                 (so its share/ is exposed). Default true; set false
  #                 when supplying a replacement desktop item via
  #                 extraPaths and you want to suppress upstream's.
  # extraPaths:     extra derivations to merge in (desktop items, etc.).
  # mainProgram:    meta.mainProgram on the resulting bundle.
  mkWrappedPackage =
    {
      pkg,
      exes ? null,
      gfx ? true,
      flags ? [ ],
      env ? { },
      unset ? [ ],
      prefix ? { },
      includeUpstream ? true,
      extraPaths ? [ ],
      mainProgram ? null,
    }:
    let
      p = requirePkgs "mkWrappedPackage";
      defaultExe = baseNameOf (lib.getExe pkg);
      exeList = if exes == null then [ defaultExe ] else exes;
      mainExe = builtins.head exeList;

      gfxOf =
        exe:
        # First exe uses gfxName (lib.getExe); rest use gfxExe (lib.getExe').
        if exe == mainExe then gfxName exe pkg else gfxExe exe pkg;

      sourceFor = exe: if gfx then "${gfxOf exe}/bin/${exe}" else "${pkg}/bin/${exe}";

      flagArgs = lib.concatMapStringsSep " " (f: "--add-flags ${lib.escapeShellArg f}") flags;
      envArgs = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") env
      );
      unsetArgs = lib.concatMapStringsSep " " (k: "--unset ${k}") unset;
      prefixArgs = lib.concatStringsSep " " (
        lib.mapAttrsToList (k: v: "--prefix ${k} : ${lib.escapeShellArg v}") prefix
      );

      hasWrapperWork = flags != [ ] || env != { } || unset != [ ] || prefix != { };

      wrapOne =
        exe:
        if hasWrapperWork then
          p.runCommand "${exe}-wrapped" { nativeBuildInputs = [ p.makeWrapper ]; } ''
            makeWrapper ${sourceFor exe} $out/bin/${exe} \
              ${flagArgs} ${envArgs} ${unsetArgs} ${prefixArgs}
          ''
        else if gfx then
          gfxOf exe
        else
          p.runCommand "${exe}-bin" { } ''
            mkdir -p $out/bin
            ln -s ${pkg}/bin/${exe} $out/bin/${exe}
          '';

      wrappedExes = map wrapOne exeList;
    in
    p.symlinkJoin {
      name = "${lib.getName pkg}-${pkg.version or "wrapped"}";
      paths = wrappedExes ++ extraPaths ++ lib.optional includeUpstream pkg;
      meta = (pkg.meta or { }) // {
        mainProgram = if mainProgram == null then mainExe else mainProgram;
        # symlinkJoin produces a single `out` that already merges every joined
        # path (bin, share/man, …). Inheriting pkg's multi-output
        # outputsToInstall (e.g. mpv's [ "out" "man" ]) would make buildEnv try
        # to install a `man` output this derivation doesn't have → eval error.
        outputsToInstall = [ "out" ];
      };
    };
}
