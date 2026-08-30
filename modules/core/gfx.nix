_: {
  flake.modules.homeManager.gfx =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      onNixOS = config.host.platform == "nixos";
      inherit (pkgs.stubbe) mkGLWrapper;

      linkAs =
        name: exe:
        pkgs.runCommand name { } ''
          mkdir -p $out/bin
          ln -s ${exe} $out/bin/${name}
        '';

      wrapAs =
        name: program:
        if onNixOS then linkAs name (lib.getExe program) else mkGLWrapper name (lib.getExe program);

      wrapExe =
        exeName: program: if onNixOS then program else mkGLWrapper exeName (lib.getExe' program exeName);

      wrap =
        program:
        if onNixOS then
          program
        else
          let
            exe = lib.getExe program;
          in
          mkGLWrapper (baseNameOf exe) exe;

      # Make a non-GL tool able to dlopen the GPU vendor libraries it probes
      # (btop loading libnvidia-ml.so for NVIDIA stats). Unlike the wrappers
      # above this is NOT a no-op on NixOS: GL apps find their drivers via
      # glvnd, but a plain dlopen by soname does not, and on NixOS the driver
      # libs live in /run/opengl-driver/lib — off the default loader path. On
      # non-NixOS, nixGL's bundle already includes those libs.
      withDriverLibs =
        program:
        let
          name = baseNameOf (lib.getExe program);
        in
        if onNixOS then
          pkgs.symlinkJoin {
            inherit name;
            paths = [ program ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/${name} \
                --suffix LD_LIBRARY_PATH : /run/opengl-driver/lib
            '';
          }
        else
          mkGLWrapper name (lib.getExe program);

      bundle =
        {
          pkg,
          exes ? null,
          gfx ? true,
          flags ? [ ],
          env ? { },
          unset ? [ ],
          prefix ? { },
          # Include the upstream package in the join, exposing its share/.
          # Set false when supplying a replacement desktop item via extraPaths.
          includeUpstream ? true,
          extraPaths ? [ ],
          mainProgram ? null,
        }:
        let
          exeList = if exes == null then [ (baseNameOf (lib.getExe pkg)) ] else exes;
          mainExe = builtins.head exeList;

          gfxOf = exe: if exe == mainExe then wrapAs exe pkg else wrapExe exe pkg;
          sourceFor = exe: if gfx then "${gfxOf exe}/bin/${exe}" else "${pkg}/bin/${exe}";

          wrapperArgs = lib.concatStringsSep " " (
            lib.concatLists [
              (map (f: "--add-flags ${lib.escapeShellArg f}") flags)
              (lib.mapAttrsToList (k: v: "--set ${k} ${lib.escapeShellArg v}") env)
              (map (k: "--unset ${k}") unset)
              (lib.mapAttrsToList (k: v: "--prefix ${k} : ${lib.escapeShellArg v}") prefix)
            ]
          );
          needsWrapper = flags != [ ] || env != { } || unset != [ ] || prefix != { };

          wrapOne =
            exe:
            if needsWrapper then
              pkgs.runCommand "${exe}-wrapped" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
                makeWrapper ${sourceFor exe} $out/bin/${exe} ${wrapperArgs}
              ''
            else if gfx then
              gfxOf exe
            else
              linkAs exe "${pkg}/bin/${exe}";
        in
        pkgs.symlinkJoin {
          name = "${lib.getName pkg}-${pkg.version or "wrapped"}";
          paths = map wrapOne exeList ++ extraPaths ++ lib.optional includeUpstream pkg;
          meta = (pkg.meta or { }) // {
            mainProgram = if mainProgram == null then mainExe else mainProgram;
            # symlinkJoin produces a single `out` that already merges every
            # joined path (bin, share/man, …). Inheriting pkg's multi-output
            # outputsToInstall (e.g. mpv's [ "out" "man" ]) would make buildEnv
            # try to install a `man` output this derivation does not have.
            outputsToInstall = [ "out" ];
          };
        };
    in
    {
      options.stubbe.gfx =
        let
          fn = lib.mkOption {
            type = lib.types.functionTo lib.types.raw;
            internal = true;
          };
          fn2 = lib.mkOption {
            type = lib.types.functionTo (lib.types.functionTo lib.types.raw);
            internal = true;
          };
        in
        {
          wrap = fn // {
            description = "Wrap a package's mainProgram for GL. Output binary keeps its own name.";
          };
          wrapAs = fn2 // {
            description = "`wrapAs <name> <pkg>`: wrap the mainProgram, exposing it under `<name>`.";
          };
          wrapExe = fn2 // {
            description = "`wrapExe <exe> <pkg>`: wrap one named binary from a package, not its mainProgram.";
          };
          withDriverLibs = fn // {
            description = "Let a non-GL tool dlopen the GPU vendor libraries it probes. Not a no-op on NixOS.";
          };
          bundle = fn // {
            description = "Wrap selected binaries of a package and symlinkJoin the result with upstream. See the source for arguments.";
          };
        };

      config.stubbe.gfx = {
        inherit
          wrap
          wrapAs
          wrapExe
          withDriverLibs
          bundle
          ;
      };
    };
}
