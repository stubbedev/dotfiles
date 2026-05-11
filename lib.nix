{
  lib,
  pkgs ? null,
  systemInfo ? null,
  self,
  isNixOS ? false,
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

  gfxLib = import ./gfx.nix { inherit lib pkgs systemInfo isNixOS; };
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
  # SOPS secrets
  # ============================================================

  # Declare a binary-mode sops secret that lives at <repo>/secrets/<name>
  # and decrypts to `path` at activation. Returns the value for
  # sops.secrets.<key>; the caller picks the attrset key.
  #
  #   sops.secrets.foo = homeLib.mkBinarySecret {
  #     name = "foo";   # secrets/foo
  #     path = "${config.home.homeDirectory}/.config/foo";
  #   };
  mkBinarySecret =
    { name, path }:
    {
      sopsFile = self + "/secrets/${name}";
      format = "binary";
      inherit path;
    };

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
      promptQuestion = "Install AppArmor profile for Nix ${appName}?";
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

  # Build the prompt args for an SDDM/GDM Wayland session entry under
  # /usr/share/wayland-sessions/<name>.desktop. The body is a Desktop
  # Entry rendered via lib.generators.toINI so callers pass attrs
  # rather than heredoc text.
  mkSddmSession =
    {
      config,
      name, # filename basename (without .desktop)
      displayName, # "Hyprland (Nix)"
      comment,
      execName, # binary in config.home.profileDirectory/bin
      desktopNames,
      extraEntries ? { }, # additional Desktop Entry keys
    }:
    let
      target = "/usr/share/wayland-sessions/${name}.desktop";
      content = lib.generators.toINI { } {
        "Desktop Entry" = {
          Name = displayName;
          Comment = comment;
          Exec = "${config.home.profileDirectory}/bin/${execName}";
          Type = "Application";
          DesktopNames = desktopNames;
        }
        // extraEntries;
      };
    in
    {
      promptTitle = "⚠️  SDDM ${displayName} session entry missing";
      promptBody = ''
        SDDM needs a desktop entry to show ${displayName} in the session menu.
        This will create the session entry.
      '';
      promptQuestion = "Create ${target}?";
      actionScript = ''
        sudo install -d -m 0755 /usr/share/wayland-sessions
        ${installSystemFile { inherit target content; }}
      '';
    };

  # ============================================================
  # Script binaries (live in config.home.profileDirectory/bin/)
  # ============================================================

  # Read a script at <repo-root>/<source>, apply @KEY@ substitutions, and
  # build it as an executable Nix derivation that lands under
  # config.home.profileDirectory/bin/<name>. Preserves the script's own shebang
  # (so zsh stays zsh, bash stays bash). Use this instead of writing
  # things to home.file.".local/bin/x" — keeps scripts on PATH and
  # owned by the Nix profile.
  mkScriptBin =
    {
      name,
      source, # path relative to repo root, e.g. "src/aerc/scripts/x.sh" or "bin/y"
      vars ? { },
    }:
    (requirePkgs "mkScriptBin").writeTextFile {
      inherit name;
      text = substituteFile {
        file = self + "/${source}";
        inherit vars;
      };
      executable = true;
      destination = "/bin/${name}";
    };

  # ============================================================
  # Live symlinks (point ~/.config/<x> at ~/.stubbe/src/<y>)
  # ============================================================

  # Render an idempotent symlink-replacement snippet. Used in non-
  # privileged activations to point a config dir at the live src/ tree
  # in the dotfiles checkout, so edits are reflected without re-running
  # home-manager. mkdir -p covers the parent; rm -rf covers both stale
  # symlinks and previously-materialised directories.
  mkLiveSymlink =
    {
      config,
      src, # subpath under ~/.stubbe/src/
      target, # path under $HOME (no leading slash)
    }:
    let
      sourcePath = "${config.home.homeDirectory}/.stubbe/src/${src}";
      targetPath = "${config.home.homeDirectory}/${target}";
    in
    ''
      mkdir -p "$(dirname "${targetPath}")"
      rm -rf "${targetPath}"
      ln -s "${sourcePath}" "${targetPath}"
    '';

  # Copy a file from the live src/ tree to a target under $HOME. Use this
  # for config files that the owning app rewrites at runtime (btop.conf,
  # lazygit state.yml, …) — a symlink would be modified in place inside
  # the dotfiles checkout, which we don't want. The activation runs on
  # every switch, so the dotfiles version is authoritative on switch.
  mkLiveCopy =
    {
      config,
      src, # subpath under ~/.stubbe/src/
      target, # path under $HOME (no leading slash)
    }:
    let
      sourcePath = "${config.home.homeDirectory}/.stubbe/src/${src}";
      targetPath = "${config.home.homeDirectory}/${target}";
    in
    ''
      mkdir -p "$(dirname "${targetPath}")"
      cat "${sourcePath}" > "${targetPath}"
    '';

  # Recursively merge `patch` (a Nix attrset) onto whatever JSON is
  # currently at `target`, writing the result back atomically.
  #
  # Use this for state files the owning app rewrites at runtime
  # (claude-code's ~/.claude.json, ~/.claude/settings.json, …). Doing
  # the merge at *activation* time — instead of `recursiveUpdate`-ing
  # against `builtins.readFile` at eval time — preserves every byte
  # the app wrote between evaluation and activation. The eval-time
  # approach silently drops anything written in that window.
  #
  # name    — basename for the rendered patch derivation in /nix/store.
  # target  — absolute path to the live JSON file.
  # patch   — attrset to merge in (right-side wins on conflicts, same
  #           semantics as lib.recursiveUpdate / jq's `*`).
  # mode    — file mode used only when target doesn't yet exist
  #           (default 0600 — most app state files want this).
  #
  # cmp-before-mv: skip the rename when the merged result is already
  # byte-identical to the live file. Avoids racing against the app's
  # own writes once the patch is in place (steady-state behaviour).
  mergeJsonPatch =
    {
      name,
      target,
      patch,
      mode ? "0600",
    }:
    let
      p = requirePkgs "mergeJsonPatch";
      patchFile = p.writeText "${name}.json" (builtins.toJSON patch);
    in
    ''
      mkdir -p "$(dirname "${target}")"
      if [ -f "${target}" ]; then
        ${p.jq}/bin/jq -s '(.[0] // {}) * .[1]' "${target}" "${patchFile}" \
          > "${target}.hm-tmp"
        if cmp -s "${target}.hm-tmp" "${target}"; then
          rm -f "${target}.hm-tmp"
        else
          mv "${target}.hm-tmp" "${target}"
        fi
      else
        install -m ${mode} "${patchFile}" "${target}"
      fi
    '';

  # ============================================================
  # Sudo-prompt scaffolding (consistent "Install X" / "Install X?")
  # ============================================================

  # Build the prompt fields from a single `subject`, then merge any
  # extra fields the caller supplies (preCheck, actionScript, body, …).
  # Title and question follow the "Installing <subject>" / "Install
  # <subject>?" form, matching the most common sudo-prompt setups.
  mkInstallPrompt =
    {
      subject,
      body,
      ...
    }@extra:
    removeAttrs extra [
      "subject"
      "body"
    ]
    // {
      promptTitle = "Installing ${subject}";
      promptQuestion = "Install ${subject}?";
      promptBody = body;
    };

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
      skipMessage ? "Skipped. Re-run 'hm switch' to retry.",
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
      printf '%s\n' ${lib.escapeShellArg promptTitle}
      echo "--------------------------------------------------------------------"
      echo ""
      printf '%s\n' ${lib.escapeShellArg promptBody}
      read -p ${lib.escapeShellArg "${promptQuestion} [Y/n] "} -n 1 -r
      echo

      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ${actionScript}
        mkdir -p "$HOME/.local/state/nix/home-manager"
        echo -n "${actionHash}" > "$lockFile"
      else
        echo ""
        printf '%s\n' ${lib.escapeShellArg skipMessage}
      fi
      echo ""
    '';

}
