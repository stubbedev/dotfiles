# Privileged-activation builders: render shell snippets that materialise
# content into system locations (root-owned files, host-OS packages,
# polkit rules, AppArmor profiles) via sudo.
#
# These are pure string builders — no pkgs needed — and are therefore
# importable by NixOS modules (polkit.nix, chrome-policy.nix) that never
# see a home-manager pkgs set.
{ lib }:
rec {

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

  # Render a shell snippet that installs host-OS packages via the first
  # available package manager when `detect` (a binary in PATH) is
  # absent. Aborts with `exit 1` on unsupported distros. Each branch
  # takes its own distro-native package list.
  #
  #   ${homeLib.installHostPackage {
  #     detect = "avahi-daemon";
  #     apt    = [ "avahi-daemon" "libnss-mdns" ];
  #     dnf    = [ "avahi" "nss-mdns" ];
  #     pacman = [ "avahi" "nss-mdns" ];
  #   }}
  installHostPackage =
    {
      detect,
      apt,
      dnf,
      pacman,
    }:
    ''
      if ! command -v ${detect} >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          # --no-install-recommends: many Debian/Ubuntu packages
          # (sddm → plasma-desktop, plymouth → snapd, …) recommend
          # entire desktop environments. Activation is opinionated
          # about what gets installed, so suppress recommends and
          # let each module list explicit deps.
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends ${lib.escapeShellArgs apt}
        elif command -v dnf >/dev/null 2>&1; then
          # --setopt=install_weak_deps=False mirrors the apt behavior.
          sudo dnf install -y --setopt=install_weak_deps=False ${lib.escapeShellArgs dnf}
        elif command -v pacman >/dev/null 2>&1; then
          # pacman has no Recommends concept; optional deps stay opt-in.
          sudo pacman -S --needed --noconfirm ${lib.escapeShellArgs pacman}
        else
          echo "No supported package manager (apt-get/dnf/pacman) found." >&2
          exit 1
        fi
      fi
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

  # Activation preCheck building blocks. These render shell snippets
  # suitable for a sudoPromptScript preCheck: the activation exits 0
  # (skipping the rest, including the sudo prompt) when the requested
  # precondition isn't met. PATH is restored to a sane default because
  # activations run with a stripped PATH and many tools (apparmor_status,
  # update-grub, …) live under /sbin or /usr/sbin.
  requireCommand = cmd: ''
    PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
    if ! command -v ${cmd} >/dev/null 2>&1; then
      exit 0
    fi
  '';

  requirePath = path: ''
    if [ ! -e "${path}" ]; then
      exit 0
    fi
  '';

  # Build the prompt args for an AppArmor profile setup. Returns the
  # attrset that mkSudoSetupModule expects. Distros like Ubuntu 24.04+
  # require a matching AppArmor profile for unprivileged user namespaces
  # used by Chromium-based sandboxes; Nix-store paths aren't covered by
  # the stock profiles, so we install one per app keyed on its store
  # path glob.
  mkAppArmorSetup =
    {
      appName, # human label, e.g. "Chrome"
      profileName, # /etc/apparmor.d/<profileName>
      programGlob, # path glob the profile applies to
      managedBy, # marker comment for the profile body
    }:
    {
      preCheck = requireCommand "apparmor_status";
      promptTitle = "Installing AppArmor profile for Nix-installed ${appName}";
      promptBody = ''
        Ubuntu 24.04 restricts unprivileged user namespaces (required by
        Chromium-based sandboxes) to binaries with a matching AppArmor
        profile. Nix-store paths aren't covered by Ubuntu's stock profiles,
        so ${appName} aborts on launch with "No usable sandbox!".

        This installs an AppArmor profile that whitelists the Nix-store
        ${appName} binary (and its sandbox helper) for unprivileged userns.
      '';
      actionScript = installApparmorProfile {
        name = profileName;
        content = ''
          # managed-by: ${managedBy}
          abi <abi/4.0>,
          include <tunables/global>
          profile ${profileName} ${programGlob} flags=(unconfined) {
            userns,
            @{exec_path} mr,
            include if exists <local/${profileName}>
          }
        '';
      };
    };
}
