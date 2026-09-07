_: {
  stubbe.pkgsLib.headroomWrap =
    { final, lib, ... }:
    {
      tool,
      pkg,
      exe ? tool,
      flags ? [ ],
      toolFlags ? [ ],
    }:
    final.runCommand "${exe}-headroom"
      {
        nativeBuildInputs = [ final.makeWrapper ];
        meta = (pkg.meta or { }) // {
          mainProgram = exe;
          outputsToInstall = [ "out" ];
        };
      }
      ''
        makeWrapper ${lib.getExe final.headroom} $out/bin/${exe} \
          --prefix PATH : ${lib.makeBinPath [ pkg ]} \
          ${lib.concatMapStringsSep " " (f: "--add-flags ${lib.escapeShellArg f}") (
            [
              "wrap"
              tool
            ]
            ++ flags
            ++ [ "--" ]
            ++ toolFlags
          )}
      '';
}
