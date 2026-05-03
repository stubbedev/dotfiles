{
  description = "NixOS installer image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      disko,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      system = "x86_64-linux";

      homeDirectory = builtins.getEnv "HOME";
      sshDirectory =
        if homeDirectory == "" then
          throw "The installer ISO reads ~/.ssh at evaluation time. Build it with --impure."
        else
          /. + "${homeDirectory}/.ssh";
      sshDirectoryEntries =
        if builtins.pathExists sshDirectory then
          builtins.readDir sshDirectory
        else
          throw "Missing SSH directory: ${homeDirectory}/.ssh";

      readSshFile =
        name:
        let
          result = builtins.tryEval (builtins.readFile (sshDirectory + "/${name}"));
        in
        if result.success then result.value else "";
      sshFileNames = lib.attrNames (
        lib.filterAttrs (_: type: type == "regular" || type == "symlink") sshDirectoryEntries
      );
      sshFiles = map (
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
      ) sshFileNames;
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
    in
    {
      nixosConfigurations.installer-iso = nixpkgs.lib.nixosSystem {
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
                (disko.packages.${system}.default)
              ];

              system.stateVersion = "26.05";
            }
          )
        ];
      };

      packages.${system} = {
        installer-iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
        default = self.packages.${system}.installer-iso;
      };
    };
}
