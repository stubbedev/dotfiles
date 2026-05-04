{
  config,
  inputs,
  lib,
  ...
}:
let
  system = "x86_64-linux";

  # Read ~/.ssh impurely so the installer image ships with the user's
  # public/private SSH keys preloaded into /root/.ssh on first boot.
  # Build with --impure to enable this; under pure eval (e.g. `nix flake
  # check`) HOME is empty and we fall back to no preloaded keys so the
  # ISO derivation still evaluates.
  homeDirectory = builtins.getEnv "HOME";
  hasHome = homeDirectory != "";
  sshDirectory = if hasHome then /. + "${homeDirectory}/.ssh" else null;
  sshDirectoryEntries =
    if hasHome && builtins.pathExists sshDirectory then builtins.readDir sshDirectory else { };

  readSshFile =
    name:
    let
      result = builtins.tryEval (builtins.readFile (sshDirectory + "/${name}"));
    in
    if result.success then result.value else "";
  sshFileNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "regular" || type == "symlink") sshDirectoryEntries
  );
  sshFiles =
    if hasHome then
      map (
        name:
        let
          content = readSshFile name;
          isPublic = lib.hasSuffix ".pub" name;
          isPrivate = lib.hasInfix "PRIVATE KEY-----" content;
        in
        {
          inherit
            name
            content
            isPublic
            isPrivate
            ;
          mode = if isPrivate then "0600" else "0644";
        }
      ) sshFileNames
    else
      [ ];
  sshKeyFiles = lib.filter (file: file.isPublic || file.isPrivate) sshFiles;
  sshAuthorizedKeys = lib.concatMap (
    file:
    if file.isPublic then
      lib.filter (line: line != "" && !(lib.hasPrefix "#" line)) (lib.splitString "\n" file.content)
    else
      [ ]
  ) sshKeyFiles;
  sshEtcFiles = lib.listToAttrs (
    map (file: {
      name = "nixos-installer/ssh/${file.name}";
      value = {
        text = file.content;
        mode = file.mode;
      };
    }) sshKeyFiles
  );

  installerNixos = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      (
        { modulesPath, pkgs, ... }:
        {
          imports = [
            "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          nixpkgs.config.allowUnfree = true;

          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
          ];

          isoImage = {
            makeEfiBootable = true;
            makeUsbBootable = true;
            squashfsCompression = "zstd -Xcompression-level 6";
          };

          boot.supportedFilesystems = [ "btrfs" ];
          boot.zfs.forceImportRoot = false;

          networking = {
            hostName = "nixos-installer";
            networkmanager.enable = true;
          };

          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };
          };

          users.users.root.openssh.authorizedKeys.keys = sshAuthorizedKeys;

          environment.etc = sshEtcFiles;

          systemd.tmpfiles.rules = [
            "d /root/.ssh 0700 root root - -"
          ]
          ++ map (
            file: "C /root/.ssh/${file.name} ${file.mode} root root - /etc/nixos-installer/ssh/${file.name}"
          ) sshKeyFiles;

          environment.systemPackages = with pkgs; [
            btrfs-progs
            curl
            git
            gptfdisk
            parted
            rsync
            inputs.disko.packages.${system}.default
          ];

          system.stateVersion = "26.05";
        }
      )
    ];
  };
in
{
  flake.nixosConfigurations.installer-iso = installerNixos;

  perSystem =
    { system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.installer-iso = installerNixos.config.system.build.isoImage;
    };
}
