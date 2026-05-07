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
        # the installed system would. Activation scripts that are gated
        # on `host.platform == "nixos"` stay no-op.
        home-manager.users.${config.host.primaryUser} = {
          imports = builtins.attrValues hmMods;
          host.platform = "nixos";
          features = {
            desktop = true;
            development = true;
            hyprland = true;
            theming = true;
            media = true;
            vpn = true;
            opencode = true;
            srv = true;
            php = false;
            k8s = true;
            claudeCode = true;
            slack = true;
          };
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
