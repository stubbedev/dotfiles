# `pkgs.stubbe` — every helper this repo needs, in one namespace, reachable
# from any module of any class without a single `specialArgs` entry.
#
# Why an overlay and not injected module args: an overlay rides on `pkgs`,
# which both the NixOS and the home-manager module systems already hand every
# module. The old `homeLib` was passed via `_module.args`, which meant it had
# to be re-imported by hand in NixOS modules, and every builder needing `pkgs`
# carried a `pkgs ? null` + lazy-throw guard for the callers that had none.
# None of that exists here.
#
# Contents:
#   * everything in `flake.lib` (pure data — colours, URLs, caches)
#   * `file`/`text`   content-addressed access to files in this repo
#   * `secret`        sops secret declarations
#   * `install*`      privileged-activation shell builders
#   * `json*`         activation-time JSON state mutators
#   * `scriptBin`     repo shell scripts as Nix bins
#   * `nixGL`/`mk*Wrapper`  graphics-wrapper primitives (policy lives in
#                     modules/core/gfx.nix, which knows the target platform)
{ config, ... }:
{
  flake.overlays.stubbe =
    final: _prev:
    let
      inherit (final) lib;
      flakeLib = config.stubbe.lib;

      # Content-addressed copy of one path inside this repo.
      #
      # Never reference `${self}/src/x` directly: `self` is the whole flake
      # source, so a derivation that names a path inside it depends on ALL of
      # it and its output hash changes on every commit (and every dirty-tree
      # edit). That churn is what made privileged activations re-prompt and
      # the home-manager generation rebuild on unrelated edits. `builtins.path`
      # hashes the file's own contents instead, so a store path here changes
      # exactly when that file changes.
      repoPath =
        relPath:
        builtins.path {
          path = flakeLib.src + "/${relPath}";
          name = lib.replaceStrings [ "/" ] [ "-" ] relPath;
        };
    in
    {
      stubbe = flakeLib // {
        # ── Repo files ──────────────────────────────────────────────────
        file = repoPath;
        text = relPath: builtins.readFile (flakeLib.src + "/${relPath}");

        # `@NAME@` substitution over a repo file, via nixpkgs' own
        # `replaceVars` (not a hand-rolled `replaceStrings`): it fails the
        # build on an unsubstituted marker or a replacement that matched
        # nothing, so a renamed placeholder is a build error instead of a
        # silently broken config.
        render =
          relPath: vars:
          final.replaceVarsWith {
            # Name it after the file, not after the content-addressed input —
            # otherwise the output carries both hashes in its store name.
            name = baseNameOf relPath;
            src = repoPath relPath;
            replacements = vars;
          };

        # Colour palette in the shapes consumers actually want. `colors` is
        # bare hex; these are the renderers, so no themed file ever hardcodes
        # a Catppuccin value.
        withHash = lib.mapAttrs (_: hex: "#${hex}") flakeLib.colors;
        withArgb = lib.mapAttrs (_: hex: "0xff${hex}") flakeLib.colors;

        # ── Secrets ─────────────────────────────────────────────────────
        # Declare a binary-mode sops secret backed by <repo>/secrets/<name>,
        # decrypted to `path` at activation. The value is what
        # `sops.secrets.<key>` expects; the caller picks the key.
        # `path` is optional: NixOS secrets land in /run/secrets/<name> by
        # default, while HM secrets normally name an explicit destination.
        secret =
          {
            name,
            path ? null,
          }:
          {
            sopsFile = flakeLib.src + "/secrets/${name}";
            format = "binary";
          }
          // lib.optionalAttrs (path != null) { inherit path; };

        # ── Privileged activation builders ──────────────────────────────
        # Each returns a shell snippet for a `stubbe.setup.<name>.script`
        # whose `privileged = true` (see modules/core/setup.nix), where a
        # `sudo` shell function is already in scope.

        # Materialise a store path into a root-owned system location.
        # Store path (not an inline heredoc): no quoting hazard, no
        # eval-time readFile, and the snippet's own hash — which gates the
        # sudo re-prompt — changes exactly when the content does.
        installFile =
          {
            source,
            target,
            mode ? "0644",
            owner ? "root",
            group ? "root",
          }:
          ''
            sudo install -D -m ${mode} -o ${owner} -g ${group} ${source} ${lib.escapeShellArg target}
          '';

        # Same, for content generated in Nix rather than kept as a repo file.
        installText =
          {
            name,
            text,
            ...
          }@args:
          final.stubbe.installFile (
            removeAttrs args [
              "name"
              "text"
            ]
            // {
              source = final.writeText name text;
            }
          );

        # Install host-OS packages via the first available package manager,
        # when `detect` is not already on PATH. Aborts on unsupported distros.
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
                # (sddm → plasma-desktop, plymouth → snapd, …) recommend entire
                # desktop environments. Activation is opinionated about what
                # gets installed, so suppress recommends and let each module
                # list explicit deps.
                sudo apt-get update
                sudo apt-get install -y --no-install-recommends ${lib.escapeShellArgs apt}
              elif command -v dnf >/dev/null 2>&1; then
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

        # Install a polkit rule and reload polkitd. Rules want root:polkitd
        # ownership where the polkitd group exists, root:root otherwise.
        installPolkitRule =
          { source, target }:
          ''
            ${final.stubbe.installFile { inherit source target; }}
            if getent group polkitd >/dev/null 2>&1; then
              sudo chown root:polkitd ${lib.escapeShellArg target}
            fi
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl restart polkit.service >/dev/null 2>&1 || true
            fi
          '';

        # Activation guards. Each exits 0 — skipping the rest of the setup,
        # including its sudo prompt — when the precondition is not met.
        # PATH is restored first: activations run with a stripped PATH and
        # many probes (apparmor_status, udevadm, …) live under /sbin.
        requireCommand = cmd: ''
          PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"
          if ! command -v ${cmd} >/dev/null 2>&1; then
            exit 0
          fi
        '';

        requirePath = path: ''
          if [ ! -e ${lib.escapeShellArg path} ]; then
            exit 0
          fi
        '';

        # A complete `stubbe.setup.<name>` body granting one Nix-store binary
        # the right to create unprivileged user namespaces.
        #
        # Ubuntu 24.04+ sets kernel.apparmor_restrict_unprivileged_userns=1,
        # which limits userns (required by Chromium-family and bubblewrap
        # sandboxes) to binaries with a matching AppArmor profile. Nix-store
        # paths are not covered by the stock profiles, so the app aborts on
        # launch ("No usable sandbox!" / "setting up uid map: Permission
        # denied"). Children stay unconfined, so nested sandboxes still work.
        apparmorSetup =
          {
            appName,
            profileName,
            programGlob,
          }:
          {
            privileged = true;
            preCheck = final.stubbe.requireCommand "apparmor_status";
            title = "Installing AppArmor profile for Nix-installed ${appName}";
            body = ''
              Ubuntu 24.04 restricts unprivileged user namespaces (required by
              Chromium-based sandboxes) to binaries with a matching AppArmor
              profile. Nix-store paths aren't covered by Ubuntu's stock profiles,
              so ${appName} aborts on launch with "No usable sandbox!".

              This installs an AppArmor profile that whitelists the Nix-store
              ${appName} binary (and its sandbox helper) for unprivileged userns.
            '';
            script = ''
              ${final.stubbe.installText {
                name = profileName;
                target = "/etc/apparmor.d/${profileName}";
                text = ''
                  # managed-by: stubbe ${profileName}
                  abi <abi/4.0>,
                  include <tunables/global>
                  profile ${profileName} ${programGlob} flags=(unconfined) {
                    userns,
                    @{exec_path} mr,
                    include if exists <local/${profileName}>
                  }
                '';
              }}
              sudo apparmor_parser -r ${lib.escapeShellArg "/etc/apparmor.d/${profileName}"}
            '';
          };

        # ── JSON state-file mutators ────────────────────────────────────
        # Both shell out to jq against the LIVE file, so every byte the owning
        # app wrote between evaluation and activation survives. Merging at eval
        # time against `builtins.readFile` would silently drop that window.
        #
        # `jsonMerge` deep-merges (additive, right wins — jq's `*`), for state
        # files an app rewrites at runtime. `jsonSet` REPLACES one top-level
        # key wholesale, so entries dropped from `value` actually disappear —
        # for a managed subtree inside an externally-owned file (mcpServers in
        # ~/.claude.json).
        jsonMerge =
          {
            name,
            target,
            patch,
            mode ? "0600",
          }:
          let
            patchFile = final.writeText "${name}.json" (builtins.toJSON patch);
          in
          ''
            mkdir -p "$(dirname ${lib.escapeShellArg target})"
            if [ -f ${lib.escapeShellArg target} ]; then
              ${lib.getExe final.jq} -s '(.[0] // {}) * .[1]' ${lib.escapeShellArg target} ${patchFile} \
                > ${lib.escapeShellArg "${target}.hm-tmp"}
              # Skip the rename when the result is already byte-identical, so
              # steady state does not race the app's own writes.
              if cmp -s ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}; then
                rm -f ${lib.escapeShellArg "${target}.hm-tmp"}
              else
                mv ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}
              fi
            else
              install -D -m ${mode} ${patchFile} ${lib.escapeShellArg target}
            fi
          '';

        jsonSet =
          {
            name,
            target,
            key,
            value,
            mode ? "0600",
          }:
          let
            valueFile = final.writeText "${name}.json" (builtins.toJSON value);
          in
          ''
            mkdir -p "$(dirname ${lib.escapeShellArg target})"
            if [ -f ${lib.escapeShellArg target} ]; then
              ${lib.getExe final.jq} --slurpfile v ${valueFile} '.[${builtins.toJSON key}] = $v[0]' \
                ${lib.escapeShellArg target} > ${lib.escapeShellArg "${target}.hm-tmp"}
              if cmp -s ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}; then
                rm -f ${lib.escapeShellArg "${target}.hm-tmp"}
              else
                mv ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}
              fi
            else
              ${lib.getExe final.jq} -n --slurpfile v ${valueFile} '{ ${builtins.toJSON key}: $v[0] }' \
                > ${lib.escapeShellArg target}
              chmod ${mode} ${lib.escapeShellArg target}
            fi
          '';

        # ── Repo scripts as Nix bins ────────────────────────────────────
        # Land under config.home.profileDirectory/bin (~/.nix-profile/bin, or
        # /etc/profiles/per-user/$USER/bin on NixOS) so they are on PATH and
        # owned by the Nix profile. The script's own shebang is preserved, so
        # zsh stays zsh. `vars` are `@NAME@` markers, validated by replaceVars.
        scriptBin =
          {
            name,
            source,
            vars ? { },
          }:
          final.replaceVarsWith {
            inherit name;
            src = repoPath source;
            replacements = vars;
            dir = "bin";
            isExecutable = true;
            # So `lib.getExe` resolves without the "assuming the main program
            # has the same name" deprecation warning.
            meta.mainProgram = name;
          };

        # ── Graphics wrapper primitives ─────────────────────────────────
        # Facts about this machine's GPU and the nixGL bundle that matches it.
        # The platform POLICY (wrap on non-NixOS, no-op on NixOS) lives in
        # modules/core/gfx.nix — these are just the building blocks.
        #
        # Requires --impure for the /proc read; the flake already runs that way.
        hasNvidia = builtins.pathExists (/. + "/proc/driver/nvidia/version");

        # `nixgl.nixGLNvidia` only exists when the overlay's eval-time version
        # detection succeeded (it reads /proc with builtins.readFile, which
        # returns "" on kernels reporting the file as zero-sized). Fall back to
        # nixGL's `auto` set, which copies the file in a runCommand and so
        # always detects.
        nixGL =
          if final.stubbe.hasNvidia then
            (final.nixgl.nixGLNvidia or final.nixgl.auto.nixGLNvidia)
          else
            final.nixgl.nixGLIntel;

        # Wrap a binary in nixGL and inject the system driver search paths, so
        # loaders find Mesa's GBM backends and DRI drivers on non-NixOS hosts.
        # `--suffix` lets user-set values win; missing paths are skipped by the
        # loader, but if NONE of a list exists EGL/GBM init fails — hence the
        # RHEL/Arch (lib64), generic (lib) and Debian multiarch layouts below.
        mkGLWrapper =
          name: programPath:
          final.runCommand name { nativeBuildInputs = [ final.makeWrapper ]; } ''
            makeWrapper ${final.stubbe.nixGLBin} $out/bin/${name} \
              --suffix GBM_BACKENDS_PATH : "${final.stubbe.driverEnv.GBM_BACKENDS_PATH}" \
              --suffix LIBGL_DRIVERS_PATH : "${final.stubbe.driverEnv.LIBGL_DRIVERS_PATH}" \
              ${lib.optionalString final.stubbe.hasNvidia ''
                --suffix LD_LIBRARY_PATH : "${final.stubbe.nvidiaEglLibs}" \
                --suffix __EGL_EXTERNAL_PLATFORM_CONFIG_FILENAMES : "${final.stubbe.nvidiaEglConfigs}" \
              ''}--add-flag "${programPath}"
          '';

        # No nixGL: for DRM/KMS contexts that need the HOST's EGL stack.
        mkDriverWrapper =
          name: programPath:
          final.runCommand name { nativeBuildInputs = [ final.makeWrapper ]; } ''
            makeWrapper ${programPath} $out/bin/${name} \
              --set GBM_BACKENDS_PATH "${final.stubbe.driverEnv.GBM_BACKENDS_PATH}" \
              --set LIBGL_DRIVERS_PATH "${final.stubbe.driverEnv.LIBGL_DRIVERS_PATH}" \
              --set __EGL_VENDOR_LIBRARY_DIRS "${final.stubbe.driverEnv.EGL_VENDOR_LIBRARY_DIRS}" \
              --set LD_LIBRARY_PATH "${final.stubbe.driverEnv.LD_LIBRARY_PATHS}" \
              --unset __EGL_VENDOR_LIBRARY_FILENAMES
          '';

        nixGLBin = "${final.stubbe.nixGL}/bin/${final.stubbe.nixGL.name}";

        driverEnv = {
          GBM_BACKENDS_PATH = lib.concatStringsSep ":" [
            "/usr/lib/x86_64-linux-gnu/gbm"
            "/usr/lib64/gbm"
            "/usr/lib/gbm"
            "/run/opengl-driver/lib/gbm"
            "/run/opengl-driver-32/lib/gbm"
          ];
          LIBGL_DRIVERS_PATH = lib.concatStringsSep ":" [
            "/usr/lib/x86_64-linux-gnu/dri"
            "/usr/lib64/dri"
            "/usr/lib/dri"
            "/run/opengl-driver/lib/dri"
            "/run/opengl-driver-32/lib/dri"
          ];
          EGL_VENDOR_LIBRARY_DIRS = lib.concatStringsSep ":" [
            "/usr/share/glvnd/egl_vendor.d"
            "/usr/local/share/glvnd/egl_vendor.d"
            "/etc/glvnd/egl_vendor.d"
          ];
          LD_LIBRARY_PATHS = lib.concatStringsSep ":" [
            "/usr/lib"
            "/usr/lib64"
          ];
        };

        # NVIDIA's libEGL_nvidia.so dlopens libnvidia-egl-wayland.so.1 and
        # libnvidia-egl-gbm.so.1 for the Wayland EGL and GBM platforms. nixGL's
        # NVIDIA bundle does NOT ship those external platform libs, so Nix-built
        # Wayland clients fail with "provided display handle is not supported"
        # on non-NixOS hosts. Add the lib dirs and register their JSON configs.
        nvidiaEglLibs = lib.optionalString final.stubbe.hasNvidia (
          lib.concatStringsSep ":" [
            "${final.egl-wayland}/lib"
            "${final.egl-gbm}/lib"
          ]
        );
        nvidiaEglConfigs = lib.optionalString final.stubbe.hasNvidia (
          lib.concatStringsSep ":" [
            "${final.egl-wayland}/share/egl/egl_external_platform.d/10_nvidia_wayland.json"
            "${final.egl-gbm}/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
          ]
        );
      };
    };
}
