{
  config,
  inputs,
  lib,
  self,
  ...
}:
let
  system = "x86_64-linux";

  # Read ~/.ssh impurely so the installer image ships with the user's
  # public/private SSH keys preloaded into /root/.ssh on first boot.
  # Build with --impure to enable this; under pure eval (e.g. `nix flake
  # check`) HOME is empty and we fall back to no preloaded keys so the
  # ISO derivation still evaluates.
  #
  # SECURITY WARNING. The resulting ISO contains UNENCRYPTED PRIVATE
  # SSH KEYS. Treat the ISO as a sensitive artefact: never publish it,
  # never put it on a shared file server, and wipe USB sticks once the
  # install is done. To narrow the blast radius, set the
  # STB_ISO_SSH_KEYS env var to a colon-separated allowlist of file
  # basenames before building, e.g.
  #   STB_ISO_SSH_KEYS=id_ed25519:id_ed25519.pub:known_hosts \
  #     nix build .#installer-iso --impure
  # When unset, every regular file under ~/.ssh is read (legacy
  # behaviour) and a build-time warning fires.
  homeDirectory = builtins.getEnv "HOME";
  hasHome = homeDirectory != "";
  sshDirectory = if hasHome then /. + "${homeDirectory}/.ssh" else null;
  sshDirectoryEntries =
    if hasHome && builtins.pathExists sshDirectory then builtins.readDir sshDirectory else { };

  sshKeyAllowlistEnv = builtins.getEnv "STB_ISO_SSH_KEYS";
  hasAllowlist = sshKeyAllowlistEnv != "";
  sshKeyAllowlist = lib.filter (s: s != "") (lib.splitString ":" sshKeyAllowlistEnv);

  readSshFile =
    name:
    let
      result = builtins.tryEval (builtins.readFile (sshDirectory + "/${name}"));
    in
    if result.success then result.value else "";
  rawSshFileNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "regular" || type == "symlink") sshDirectoryEntries
  );
  rawSshFileNamesFiltered =
    if hasAllowlist then lib.filter (n: lib.elem n sshKeyAllowlist) rawSshFileNames else rawSshFileNames;
  sshFileNames =
    if hasHome && !hasAllowlist && rawSshFileNamesFiltered != [ ] then
      lib.warn ''
        installer-iso: STB_ISO_SSH_KEYS not set — baking ALL ~/.ssh files
        into the ISO. The resulting image carries unencrypted private
        keys; treat it as sensitive. Set STB_ISO_SSH_KEYS=key1:key2:...
        to narrow the allowlist.
      '' rawSshFileNamesFiltered
    else
      rawSshFileNamesFiltered;
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
  nixosMods = config.flake.modules.nixos;
  hmMods = config.flake.modules.homeManager;
in
{
  configurations.nixos.installer-iso = {
    inherit system;
    extraSpecialArgs = { inherit self; };
    module =
      {
        config,
        lib,
        modulesPath,
        pkgs,
        ...
      }:
      {
        imports = [
          "${modulesPath}/installer/cd-dvd/installation-cd-graphical-base.nix"
        ] ++ builtins.attrValues nixosMods;

        isoImage = {
          makeEfiBootable = true;
          makeUsbBootable = true;
          squashfsCompression = "zstd -Xcompression-level 6";
        };

        boot.zfs.forceImportRoot = false;

        networking.hostName = lib.mkForce "stubbe-iso";

        # The ISO's only job is to run stb-install-nixos. Skip greetd and
        # autologin root on tty1 so the live boot lands directly at a root
        # shell. The installed system still uses greetd from
        # modules/nixos/greetd.nix; this override is scoped to the ISO.
        services.greetd.enable = lib.mkForce false;
        services.getty.autologinUser = lib.mkForce "root";
        users.users.root.initialHashedPassword = lib.mkForce "";

        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "prohibit-password";
          };
        };

        users.users.root.openssh.authorizedKeys.keys = sshAuthorizedKeys;

        environment.etc = sshEtcFiles // {
          # Surface the flake source at /etc/nixos so
          # `nixos-install --flake /etc/nixos#stubbe-nixos`
          # (run by stb-install-nixos) resolves without arguments.
          "nixos".source = self;
        };

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
          # Wrap bin/stb-install-nixos as a system package so root can call
          # it from a tty without depending on the HM-user profile being
          # built first.
          (pkgs.writeShellScriptBin "stb-install-nixos" (
            builtins.readFile (self + "/bin/stb-install-nixos")
          ))
        ];

        # Stage the live ISO's HM user identically to the post-install
        # stubbe-nixos host so live-boot drops you into the same desktop
        # the installed system would. Feature profile comes from
        # modules/home-manager/feature-defaults.nix via hmMods; activation
        # scripts gated on `host.platform == "nixos"` stay no-op.
        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues hmMods;
          host.platform = "nixos";
        };

        system.stateVersion = "26.05";
      };
  };

  perSystem =
    { system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.installer-iso = config.flake.nixosConfigurations.installer-iso.config.system.build.isoImage;
    };
}
