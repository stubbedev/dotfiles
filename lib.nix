{
  lib,
  pkgs ? null,
  systemInfo ? null,
  self,
  ...
}:
let
  requirePkgs =
    name: if pkgs == null then throw "homeLib.${name}: pkgs is required" else pkgs;
in
rec {
  # ============================================================
  # GFX wrappers (nixGL)
  # ============================================================

  gfxLib = import ./gfx.nix { inherit lib pkgs systemInfo; };
  inherit (gfxLib)
    gfx
    gfxName
    gfxExe
    gfxDirectWithDrivers
    ;

  # ============================================================
  # XDG config sources
  # ============================================================

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
      } // (removeAttrs extra [ "target" ]);
    };

  # Bulk variant: map a list of paths with no extra args.
  xdgSources = paths: lib.foldl' (acc: p: acc // xdgSource p { }) { } paths;

  # Read raw text of a file under src/ at evaluation time. Pair with
  # builtins.fromJSON / fromTOML when you need parsed data.
  xdgContent = path: builtins.readFile (self + "/src/${path}");

  # ============================================================
  # Template substitution
  # ============================================================

  # Read `file` and replace each @KEY@ marker with the corresponding
  # value from `vars`. Used for files whose content depends on the
  # user's home directory / username and which are baked at eval time.
  substituteFile =
    { file, vars }:
    builtins.replaceStrings
      (map (k: "@${k}@") (lib.attrNames vars))
      (lib.attrValues vars)
      (builtins.readFile file);

  # ============================================================
  # System file installation (privileged activations)
  # ============================================================

  # Render a shell snippet that materialises `content` into `target`
  # via sudo install + chown. Caller decides what to run after (e.g.
  # apparmor_parser, systemctl reload).
  #
  # Uses a unique heredoc sentinel so embedded $VARS in `content` aren't
  # expanded by the parent shell. The temp file is cleaned up on success;
  # set -e ensures we abort early on failure (and mktemp's /tmp file gets
  # GC'd by the OS in that case).
  installSystemFile =
    {
      content,
      target,
      mode ? "0644",
      owner ? "root",
      group ? "root",
    }:
    ''
      _stb_tmp=$(mktemp)
      cat > "$_stb_tmp" << '__STB_INSTALL_EOF__'
      ${content}__STB_INSTALL_EOF__
      sudo install -m ${mode} "$_stb_tmp" "${target}"
      sudo chown ${owner}:${group} "${target}"
      rm -f "$_stb_tmp"
    '';

  # Install a polkit rule and reload the polkit service. Polkit rules
  # want root:polkitd ownership when the polkitd group exists (newer
  # distros), root:root otherwise.
  installPolkitRule =
    { content, target }:
    ''
      ${installSystemFile { inherit content target; }}
      if getent group polkitd >/dev/null 2>&1; then
        sudo chown root:polkitd "${target}"
      fi
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl restart polkit.service >/dev/null 2>&1 || true
      fi
    '';

  # Install an AppArmor profile under /etc/apparmor.d/ and reload it.
  # The preCheck pattern (skip if apparmor is absent) is the caller's
  # responsibility — this assumes apparmor_parser exists.
  installApparmorProfile =
    { name, content }:
    let
      target = "/etc/apparmor.d/${name}";
    in
    ''
      ${installSystemFile { inherit content target; }}
      sudo apparmor_parser -r "${target}"
    '';

  # ============================================================
  # Compositor session-path resolution
  # ============================================================

  # Resolve config.home.sessionPath / sessionVariables.XDG_DATA_DIRS into
  # ":"-joined absolute strings, suitable for makeWrapper --prefix. $HOME
  # placeholders get expanded against config.home.homeDirectory; the
  # literal $XDG_DATA_DIRS placeholder (which the home-manager schema
  # injects) is dropped.
  resolveSessionPaths =
    config:
    let
      homeDir = config.home.homeDirectory;
      replaceHome = path: lib.replaceStrings [ "$HOME" ] [ homeDir ] path;
      isPlaceholder = v: v == "$XDG_DATA_DIRS" || v == "\${XDG_DATA_DIRS}";

      paths = map replaceHome config.home.sessionPath;
      rawDataDirs = lib.splitString ":" (config.home.sessionVariables.XDG_DATA_DIRS or "");
      dataDirs = map replaceHome (builtins.filter (v: v != "" && !isPlaceholder v) rawDataDirs);
    in
    {
      pathPrefix = lib.concatStringsSep ":" paths;
      dataDirsPrefix = lib.concatStringsSep ":" dataDirs;
    };

  # ============================================================
  # Wrapped-package bundling
  # ============================================================

  # Wrap a package's binaries with nixGL + makeWrapper, then bundle the
  # result back together with the upstream paths via symlinkJoin. This
  # collapses the gfx-wrap → makeWrapper → symlinkJoin pattern that
  # repeats for chrome / slack / logseq / firefox / remmina.
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
      };
    };

  # ============================================================
  # Sudo prompt scaffolding (used by mkSudoSetupModule)
  # ============================================================

  sudoPromptScript =
    {
      pkgs,
      name,
      preCheck ? "",
      promptTitle,
      promptBody,
      promptQuestion,
      actionScript,
      skipMessage ? "Skipped.",
    }:
    let
      actionHash = builtins.hashString "sha256" actionScript;
    in
    pkgs.writeShellScript name ''
      set -e

      SUDO=""
      for path in /bin/sudo /usr/bin/sudo /usr/local/bin/sudo; do
        if [ -x "$path" ]; then
          SUDO="$path"
          break
        fi
      done

      # We return if no sudo is found
      if [ -z "$SUDO" ]; then
        return 0
      fi

      sudo() { "$SUDO" "$@"; }

      lockFile="$HOME/.local/state/nix/home-manager/${name}.lock.sum"
      if [ -f "$lockFile" ] && [ "$(cat "$lockFile")" = "${actionHash}" ]; then
        exit 0
      fi

      ${preCheck}

      echo ""
      echo "--------------------------------------------------------------------"
      echo "${promptTitle}"
      echo "--------------------------------------------------------------------"
      echo ""
      echo "${promptBody}"
      read -p "${promptQuestion} [Y/n] " -n 1 -r
      echo

      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ${actionScript}
        mkdir -p "$HOME/.local/state/nix/home-manager"
        echo -n "${actionHash}" > "$lockFile"
      else
        echo ""
        echo "${skipMessage}"
      fi
      echo ""
    '';

  # ============================================================
  # VPN scripts
  # ============================================================

  # Load VPN scripts from src/vpn/<provider>/{connect,disconnect,status}.sh
  # Returns attrset for home.file that maps VPN scripts to ~/.local/bin
  loadVpnScripts =
    vpnDir:
    let
      vpnProviders = lib.filterAttrs (_: type: type == "directory") (builtins.readDir vpnDir);

      createScriptEntries =
        providerName:
        let
          providerPath = vpnDir + "/${providerName}";
          scripts = [
            "connect"
            "disconnect"
            "status"
          ];

          createEntry =
            scriptName:
            let
              scriptPath = providerPath + "/${scriptName}.sh";
              binName = ".local/bin/${providerName}-vpn-${scriptName}";
            in
            if builtins.pathExists scriptPath then
              {
                name = binName;
                value.source = scriptPath;
              }
            else
              null;
        in
        builtins.filter (x: x != null) (map createEntry scripts);
    in
    builtins.listToAttrs (lib.flatten (map createScriptEntries (lib.attrNames vpnProviders)));
}
