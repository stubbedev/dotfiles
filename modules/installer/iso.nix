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
          "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
        ] ++ builtins.attrValues nixosMods;

        isoImage = {
          makeEfiBootable = true;
          makeUsbBootable = true;
          squashfsCompression = "zstd -Xcompression-level 6";
        };

        boot.zfs.forceImportRoot = false;

        # stb-install-nixos creates btrfs volumes and a vfat EFI partition.
        # Explicit declaration ensures the kernel modules are present and
        # fsck helpers are included even if cd-base doesn't pull them in.
        boot.supportedFilesystems = lib.mkAfter [ "btrfs" "vfat" ];

        # Auto-load common wired NIC drivers. nixos-install fetches packages
        # from cache.nixos.org — a missing driver means a stalled install.
        # hardware.nix covers storage controllers; these cover the NIC side.
        boot.kernelModules = lib.mkAfter [
          # --- Wired ethernet ---
          "r8169"       # Realtek Gigabit PCIe (most consumer boards)
          "r8168"       # Realtek Gigabit alt driver
          "r8152"       # Realtek USB ethernet
          "e1000"       # Intel Gigabit (older)
          "e1000e"      # Intel Gigabit (NUCs, ThinkPads)
          "igb"         # Intel Gigabit (server / newer)
          "ixgbe"       # Intel 10G
          "i40e"        # Intel 40G / X710
          "tg3"         # Broadcom Gigabit
          "bnx2x"       # Broadcom 10G
          "sky2"        # Marvell Gigabit
          "atl1c"       # Qualcomm/Atheros wired
          "alx"         # Qualcomm/Atheros wired (newer)
          "forcedeth"   # nForce onboard
          # USB ethernet dongles
          "ax88179_178a" # ASIX USB 3.0 ethernet (common dongles)
          "cdc_ether"    # Generic CDC ethernet / USB tethering
          "cdc_ncm"      # CDC NCM (4G modems, some hubs)
          "r8153_ecm"    # Realtek USB 3.0 ethernet
          "lan78xx"      # Microchip USB 3.0 ethernet
          "smsc75xx"     # SMSC USB ethernet
          "smsc95xx"     # SMSC USB ethernet (Raspberry Pi style)

          # --- WiFi ---
          "iwlwifi"     # Intel WiFi 4/5/6/6E/7 (dominant in laptops)
          "iwldvm"      # Intel WiFi 4000 series firmware driver
          "iwlmvm"      # Intel WiFi 5000+ series firmware driver
          "ath9k"       # Qualcomm 802.11n PCIe
          "ath9k_htc"   # Qualcomm 802.11n USB
          "ath10k_pci"  # Qualcomm 802.11ac PCIe
          "ath11k_pci"  # Qualcomm 802.11ax PCIe
          "rtw88_pci"   # Realtek 802.11ac PCIe
          "rtw88_8822be" "rtw88_8822ce" "rtw88_8821ce" # Realtek 802.11ac chips
          "rtw89_pci"   # Realtek 802.11ax PCIe
          "rtw89_8852be" "rtw89_8852ce" # Realtek 802.11ax chips
          "mt7921e"     # MediaTek 802.11ax PCIe (AMD budget laptops)
          "mt7915e"     # MediaTek 802.11ax PCIe (newer)
          "mt7601u"     # MediaTek USB WiFi (cheap dongles)
          "brcmfmac"    # Broadcom FullMAC (common in Macs, RPi, Chromebooks)
          "brcmsmac"    # Broadcom SoftMAC
          "b43"         # Broadcom 43xx (older)

          # --- Bluetooth (useful if WiFi uses BT coexistence firmware) ---
          "btusb"       # USB Bluetooth (covers most BT dongles + built-in)
          "btintel"     # Intel Bluetooth
          "btrtl"       # Realtek Bluetooth
          "btmtk"       # MediaTek Bluetooth

          # --- Input (belt-and-suspenders over hardware.nix) ---
          "hid_generic" # Generic HID fallback
          "i2c_hid"     # I2C HID (laptop touchpads/keyboards)
          "i2c_hid_acpi"
        ];

        # All firmware blobs including non-redistributable (Broadcom WiFi,
        # some Intel/Realtek). Needed for brcmfmac, some iwlwifi revisions,
        # and various USB WiFi chips.
        hardware.enableAllFirmware = true;
        nixpkgs.config.allowUnfree = true;

        networking.hostName = lib.mkForce "stubbe-iso";

        # The ISO's only job is to run stb-install-nixos. Skip greetd and
        # autologin root on tty1 so the live boot lands directly at a root
        # shell. The installed system still uses greetd from
        # modules/nixos/greetd.nix; this override is scoped to the ISO.
        services.greetd.enable = lib.mkForce false;
        services.displayManager.sddm.enable = lib.mkForce false;

        # graphics.nix enables nvidia-open; the minimal ISO has no X11 so the
        # module would still be loaded at boot and fail on non-NVIDIA hardware.
        services.xserver.enable = lib.mkForce false;
        hardware.nvidia = {
          modesetting.enable = lib.mkForce false;
          open = lib.mkForce false;
        };
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
          "nixos/dotfiles".source = self;
          "profile.d/stb-welcome.sh".text = ''
            [ "$(id -u)" -eq 0 ] || return 0
            printf '\n\033[1;32m=== stubbe NixOS Installer ===\033[0m\n'
            printf 'Run \033[1mstb-install-nixos\033[0m to detect, partition, and install.\n\n'
          '';
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
          (pkgs.writeShellScriptBin "stb-install-nixos" (
            builtins.readFile (self + "/bin/stb-install-nixos")
          ))
        ];

        system.stateVersion = "26.05";
      };
  };

  perSystem =
    { pkgs, system, ... }:
    let
      iso = config.flake.nixosConfigurations.installer-iso.config.system.build.isoImage;
      # Boot the freshly-built ISO under qemu/KVM with EFI firmware and a
      # persistent virtio disk, so stb-install-nixos can be exercised end-
      # to-end without burning a USB stick. Disk path overridable via the
      # ISO_VM_DISK env var; defaults to /tmp/stb-installer-vm.qcow2.
      iso-vm = pkgs.writeShellApplication {
        name = "installer-iso-vm";
        runtimeInputs = [
          pkgs.qemu
          pkgs.OVMFFull
        ];
        text = ''
          set -euo pipefail
          iso_path=$(echo ${iso}/iso/*.iso)
          disk="''${ISO_VM_DISK:-/tmp/stb-installer-vm.qcow2}"
          if [ ! -f "$disk" ]; then
            echo "Creating fresh 32G install disk at $disk"
            qemu-img create -f qcow2 "$disk" 32G
          fi
          exec qemu-system-x86_64 \
            -enable-kvm -cpu host -m 4096 -smp 4 \
            -bios ${pkgs.OVMFFull.fd}/FV/OVMF.fd \
            -cdrom "$iso_path" \
            -drive file="$disk",if=virtio,format=qcow2 \
            -boot d \
            -netdev user,id=net0 -device virtio-net-pci,netdev=net0
        '';
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.installer-iso = iso;
      packages.installer-iso-vm = iso-vm;
      apps.installer-iso-vm = {
        type = "app";
        program = lib.getExe iso-vm;
      };
    };
}
