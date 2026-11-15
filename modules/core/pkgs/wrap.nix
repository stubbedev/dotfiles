_: {
  stubbe.pkgsLib = {
    wrapPackage =
      { final, lib, ... }:
      {
        pkg,
        exes ? [ (baseNameOf (lib.getExe pkg)) ],
        flags ? [ ],
        env ? { },
        unset ? [ ],
        prefix ? { },
        suffix ? { },
        run ? [ ],
        includeUpstream ? true,
      }:
      let
        wrapperArgs = lib.escapeShellArgs (
          lib.concatLists [
            (lib.concatMap (f: [
              "--add-flags"
              f
            ]) flags)
            (lib.concatLists (
              lib.mapAttrsToList (k: v: [
                "--set"
                k
                v
              ]) env
            ))
            (lib.concatMap (k: [
              "--unset"
              k
            ]) unset)
            (lib.concatLists (
              lib.mapAttrsToList (k: v: [
                "--prefix"
                k
                ":"
                v
              ]) prefix
            ))
            (lib.concatLists (
              lib.mapAttrsToList (k: v: [
                "--suffix"
                k
                ":"
                v
              ]) suffix
            ))
            (lib.concatMap (c: [
              "--run"
              c
            ]) run)
          ]
        );
      in
      final.symlinkJoin {
        name = "${lib.getName pkg}-${pkg.version or "wrapped"}";
        paths = [
          (final.runCommand "${lib.getName pkg}-wrappers" { nativeBuildInputs = [ final.makeWrapper ]; } (
            lib.concatMapStrings (exe: ''
              makeWrapper ${lib.getExe' pkg exe} $out/bin/${exe} ${wrapperArgs}
            '') exes
          ))
        ]
        ++ lib.optional includeUpstream pkg;
        meta = (pkg.meta or { }) // {
          mainProgram = builtins.head exes;
          outputsToInstall = [ "out" ];
        };
      };

    withDriverLibs =
      { stubbe, ... }:
      pkg:
      stubbe.wrapPackage {
        inherit pkg;
        suffix.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      };
  };
}
