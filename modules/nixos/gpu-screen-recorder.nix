_: {
  # Promptless screen recording on this host. `programs.gpu-screen-recorder`
  # both installs the package system-wide AND installs a setcap wrapper for
  # gsr-kms-server (cap_sys_admin+ep), which is what lets monitor/KMS capture
  # work without a polkit prompt on every record. This is vendor-neutral —
  # KMS capture goes through gsr-kms-server on AMD and Intel just as it does
  # on NVIDIA, so the same wrapper covers every GPU. It drives the waybar
  # widget + screen-record toggle script on Wayland.
  #
  # On non-NixOS hosts this binary is supplied via home-manager instead (see
  # modules/packages/media.nix, nixGL-wrapped); there's no setcap path there,
  # so the first capture may prompt via polkit.
  flake.modules.nixos.gpuScreenRecorder =
    { config, lib, ... }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
    in
    lib.mkIf (hmFeatures.media or false) {
      programs.gpu-screen-recorder.enable = true;
    };
}
