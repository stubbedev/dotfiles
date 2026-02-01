{
  lib,
  pkgs ? null,
  systemInfo ? null,
  ...
}:
rec {
  gfxLib = import ./gfx.nix { inherit lib pkgs systemInfo; };
  inherit (gfxLib) gfx gfxExe gfxBinIncDrivers gfxBinExeIncDrivers;

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
    path:
    let
      baseDir = ./../..;
      fullPath = stringToPath (toString baseDir + "/${path}");
    in
    {
      "${path}".source = fullPath;
    };

  xdgSources = paths: lib.foldl' (acc: path: acc // xdgSource path) { } paths;

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
    pkgs.writeShellScript name ''
      set -e

      # Find sudo in common locations
      SUDO=""
      for path in /usr/bin/sudo /bin/sudo /run/wrappers/bin/sudo; do
        if [ -x "$path" ]; then
          SUDO="$path"
          break
        fi
      done

      if [ -z "$SUDO" ]; then
        echo "Error: sudo not found. Please install sudo or run manually."
        exit 1
      fi

      ${preCheck}

      echo ""
      echo "--------------------------------------------------------------------"
      echo "${promptTitle}"
      echo "--------------------------------------------------------------------"
      echo ""
      ${promptBody}
      read -p "${promptQuestion} [Y/n] " -n 1 -r
      echo

      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ${actionScript}
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
