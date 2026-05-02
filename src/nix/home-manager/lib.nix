{
  lib,
  pkgs ? null,
  systemInfo ? null,
  ...
}:
rec {
  gfxLib = import ./gfx.nix { inherit lib pkgs systemInfo; };
  inherit (gfxLib)
    gfx
    gfxName
    gfxExe
    gfxDirectWithDrivers
    ;

  # Convert string path to path type
  stringToPath =
    path:
    if builtins.isPath path then
      path
    else
      let
        pathString = toString path;
      in
      if lib.hasPrefix "/" pathString then /. + pathString else ./. + pathString;

  xdgSource =
    path: extra:
    let
      baseDir = ./../..;
      fullPath = stringToPath (toString baseDir + "/${path}");
    in
    {
      "${path}" = {
        source = fullPath;
        force = true;
      } // extra;
    };

  xdgSources = paths: lib.foldl' (acc: path: acc // (xdgSource path { })) { } paths;

  xdgSourceWith = path: extra: xdgSource path extra;

  # Read the contents of a source file under src/ at evaluation time. Pair
  # with builtins.fromJSON / fromTOML when you need parsed data, e.g.:
  #   builtins.fromJSON (homeLib.xdgContent "opencode/opencode.json")
  xdgContent =
    path:
    let
      baseDir = ./../..;
      fullPath = stringToPath (toString baseDir + "/${path}");
    in
    builtins.readFile fullPath;

  # Like xdgSource, but lets the target path under ~/.config differ from the
  # source path under src/. Use when an upstream tool refuses to look in a
  # subdirectory (e.g. cship reads ~/.config/cship.toml only).
  xdgSourceAt =
    target: source:
    let
      baseDir = ./../..;
      fullPath = stringToPath (toString baseDir + "/${source}");
    in
    {
      "${target}" = {
        source = fullPath;
        force = true;
      };
    };

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

  # Load VPN scripts from src/vpn/<provider>/{connect,disconnect,status}.sh
  # Returns attrset for home.file that maps VPN scripts to ~/.local/bin
  loadVpnScripts =
    vpnDir:
    let
      vpnProviders = lib.filterAttrs (name: type: type == "directory") (builtins.readDir vpnDir);

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

          entries = map createEntry scripts;
        in
        builtins.filter (x: x != null) entries;

      allEntries = lib.flatten (map createScriptEntries (lib.attrNames vpnProviders));
    in
    builtins.listToAttrs allEntries;

  # Load VPN config files from src/vpn/*/get-password.sh
  # Returns attrset for xdg.configFile
  # Note: config and password.gpg files are created by setup scripts in ~/.config/vpn/<provider>/
  loadVpnConfigs =
    vpnDir:
    let
      vpnProviders = lib.filterAttrs (name: type: type == "directory") (builtins.readDir vpnDir);

      createConfigEntry =
        providerName:
        let
          providerPath = vpnDir + "/${providerName}";
          getPasswordPath = providerPath + "/get-password.sh";
        in
        if builtins.pathExists getPasswordPath then
          {
            name = "vpn/${providerName}/get-password.sh";
            value = {
              source = getPasswordPath;
              executable = true;
            };
          }
        else
          null;

      entries = map createConfigEntry (lib.attrNames vpnProviders);
    in
    builtins.listToAttrs (builtins.filter (x: x != null) entries);
}
