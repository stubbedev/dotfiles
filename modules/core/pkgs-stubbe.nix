# Layer 2 of three. Where a helper belongs is decided by what it needs:
#
#   stubbe.lib.*     (modules/core/lib.nix)  pure data and pure functions -
#                    colors, theme, src. Needs nothing, so the overlay itself
#                    can consume it without recursion.
#   pkgs.stubbe.*    (here)                  anything that BUILDS: gen/conf
#                    writers, bashApp, shellScript, the gl wrappers. Needs pkgs.
#                    Re-exports all of stubbe.lib, so pkgs.stubbe.colors works.
#   config.stubbe.*  (paths/gfx/setup/mutable/mcp)  needs the evaluated config
#                    ($HOME, hostname, features) or must merge contributions
#                    from many modules.
#
# Within this file: gen/conf/bashApp/zshApp/shellScript produce derivations,
# while everything under `setup` produces shell text for a
# config.stubbe.setup.<name>.script.
{ config, ... }:
{
  flake.overlays.stubbe =
    final: _prev:
    let
      inherit (final) lib;
      flakeLib = config.stubbe.lib;

      # Never reference ${self}/src/x directly: that depends on the whole flake
      # source, so the hash churns on every commit and privileged activations
      # re-prompt. builtins.path hashes the file's own contents.
      fileNameOf = relPath: lib.replaceStrings [ "/" ] [ "-" ] relPath;

      # hyprlang: bare `key = value` lines, nested `section { }` blocks, and
      # repeated keys for list values (bind = ..., bind = ...).
      toHyprlang =
        let
          atom =
            v:
            if lib.isBool v then
              lib.boolToString v
            else if lib.isList v then
              lib.concatMapStringsSep "," atom v
            else
              toString v;
          render =
            indent: attrs:
            lib.concatStrings (
              lib.mapAttrsToList (
                name: value:
                if value == null then
                  ""
                else if lib.isAttrs value then
                  "${indent}${name} {\n${render "  ${indent}" value}${indent}}\n"
                else if lib.isList value then
                  lib.concatMapStrings (v: "${indent}${name} = ${atom v}\n") value
                else
                  "${indent}${name} = ${atom value}\n"
              ) attrs
            );
        in
        render "";

      # rasi: `@import`/`@theme` directives plus `selector { prop: value; }`
      # blocks. Strings are quoted unless they are a rasi reference (@name), a
      # colour literal (#rrggbb), or wrapped in stubbe.rasiLiteral.
      toRasi =
        {
          imports ? [ ],
          theme ? null,
          sections ? { },
        }:
        let
          value =
            v:
            if lib.isAttrs v && v ? __rasi then
              v.__rasi
            else if lib.isBool v then
              lib.boolToString v
            else if lib.isList v then
              "[ ${lib.concatMapStringsSep ", " value v} ]"
            else if lib.isString v && (lib.hasPrefix "@" v || lib.hasPrefix "#" v) then
              v
            else if lib.isString v then
              "\"${v}\""
            else
              toString v;
          block =
            selector: props:
            "${selector} {\n${lib.concatStrings (lib.mapAttrsToList (k: v: "  ${k}: ${value v};\n") props)}}\n";
        in
        lib.concatStrings (
          map (i: "@import \"${i}\"\n") imports
          ++ [ (lib.optionalString (imports != [ ]) "\n") ]
          ++ lib.mapAttrsToList block sections
          ++ lib.optional (theme != null) "@theme \"${theme}\"\n"
        );

      shellFile =
        {
          name,
          text,
          bin ? false,
        }:
        final.writeTextFile {
          inherit name;
          executable = true;
          destination = lib.optionalString bin "/bin/${name}";
          meta.mainProgram = name;
          text = ''
            #!${final.runtimeShell}
            ${text}'';
          checkPhase = ''
            ${final.stdenv.shellDryRun} "$target"
            ${lib.getExe final.shellcheck} -S warning "$target"
          '';
        };

      repoPath =
        relPath:
        builtins.path {
          path = flakeLib.src + "/${relPath}";
          name = lib.replaceStrings [ "/" ] [ "-" ] relPath;
        };
    in
    {
      stubbe = flakeLib // {
        file = repoPath;

        withHash = lib.mapAttrs (_: hex: "#${hex}") flakeLib.colors;
        withArgb = lib.mapAttrs (_: hex: "0xff${hex}") flakeLib.colors;

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

        # A store path, not a heredoc: the snippet hash gates the sudo
        # re-prompt, so it must change exactly when the content does.
        # Shell fragments for stubbe.setup.<name>.script - these emit text,
        # unlike gen/conf/bashApp above, which build derivations.
        setup = {
          file =
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

          link =
            { source, target }:
            ''
              sudo install -d -m 0755 ${lib.escapeShellArg (dirOf target)}
              sudo ln -sfT ${source} ${lib.escapeShellArg target}
            '';

          text =
            {
              name,
              text,
              ...
            }@args:
            final.stubbe.setup.file (
              removeAttrs args [
                "name"
                "text"
              ]
              // {
                source = final.writeText name text;
              }
            );

          hostPackage =
            {
              detect,
              apt,
              dnf,
              pacman,
            }:
            ''
              if ! command -v ${detect} >/dev/null 2>&1; then
                if command -v apt-get >/dev/null 2>&1; then
                  sudo apt-get update
                  sudo apt-get install -y --no-install-recommends ${lib.escapeShellArgs apt}
                elif command -v dnf >/dev/null 2>&1; then
                  sudo dnf install -y --setopt=install_weak_deps=False ${lib.escapeShellArgs dnf}
                elif command -v pacman >/dev/null 2>&1; then
                  sudo pacman -S --needed --noconfirm ${lib.escapeShellArgs pacman}
                else
                  echo "No supported package manager (apt-get/dnf/pacman) found." >&2
                  exit 1
                fi
              fi
            '';

          # Rules want root:polkitd where that group exists, root:root otherwise.
          polkitRule =
            { source, target }:
            ''
              ${final.stubbe.setup.file { inherit source target; }}
              if getent group polkitd >/dev/null 2>&1; then
                sudo chown root:polkitd ${lib.escapeShellArg target}
              fi
              if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl restart polkit.service >/dev/null 2>&1 || true
              fi
            '';

          # Each exits 0 so the rest of the setup, including its sudo prompt, is
          # skipped. PATH is restored first: activations run stripped and many
          # probes live under /sbin.
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

          # Ubuntu 24.04+ limits unprivileged userns to binaries with a matching
          # AppArmor profile, and nix-store paths match none of the stock ones, so
          # Chromium and bubblewrap abort with "No usable sandbox!".
          apparmor =
            {
              appName,
              profileName,
              programGlob,
            }:
            {
              privileged = true;
              preCheck = final.stubbe.setup.requireCommand "apparmor_status";
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
                ${final.stubbe.setup.text {
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

          # jq against the LIVE file, so anything the owning app wrote between
          # evaluation and activation survives.
          # jsonMerge is additive; jsonSet REPLACES one key, so entries dropped
          # from `value` actually disappear.
          jsonMerge =
            {
              name,
              target,
              patch,
              mode ? "0600",
            }:
            let
              patchFile = (final.formats.json { }).generate "${name}.json" patch;
            in
            ''
              mkdir -p "$(dirname ${lib.escapeShellArg target})"
              if [ -f ${lib.escapeShellArg target} ]; then
                ${lib.getExe final.jq} -s '(.[0] // {}) * .[1]' ${lib.escapeShellArg target} ${patchFile} \
                  > ${lib.escapeShellArg "${target}.hm-tmp"}
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
              valueFile = (final.formats.json { }).generate "${name}.json" value;
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

          # ── Config generators ──────────────────────────────────────────────
          # gen.<fmt> name value -> store path. conf.<fmt> maps
          # { "<path>" = <value>; } straight into xdg.configFile shape, so a
          # module states each config file once instead of repeating its name and
          # reaching for lib.mkMerge.
        };

        gen =
          let
            viaFormat = fmt: name: fmt.generate name;
            viaText =
              render: name: value:
              final.writeText name (render value);
          in
          {
            json = viaFormat (final.formats.json { });
            toml = viaFormat (final.formats.toml { });
            yaml = viaFormat (final.formats.yaml { });
            ini = viaText (lib.generators.toINI { });
            # nixpkgs has no writer for these two: hyprlang lives in
            # home-manager's module lib and rasi is private to its rofi module,
            # so neither is reachable from an overlay.
            hyprlang = viaText toHyprlang;
            rasi = viaText toRasi;
          };

        conf = lib.mapAttrs (
          _: writer: lib.mapAttrs (path: value: { source = writer (fileNameOf path) value; })
        ) final.stubbe.gen;

        # Escape hatch for rasi values that are neither string nor number:
        # sizes, insets, and anything else rasi wants unquoted.
        rasiLiteral = raw: { __rasi = raw; };

        # -S warning, not the default style severity, which fails builds on
        # cosmetic findings.
        bashApp =
          {
            name,
            text,
            runtimeInputs ? [ ],
          }:
          final.writeShellApplication {
            inherit name text runtimeInputs;
            checkPhase = ''
              runHook preCheck
              ${final.stdenv.shellDryRun} "$target"
              ${lib.getExe final.shellcheck} -S warning "$target"
              runHook postCheck
            '';
          };

        # Drop-in replacements for writeShellScript/writeShellScriptBin that add
        # bashApp's checks. Separate from bashApp because writeShellApplication
        # always prepends `set -euo pipefail`, which rewrites the control flow of
        # scripts not written for it; these keep plain semantics and only add the
        # syntax check and shellcheck.
        shellScript = name: text: shellFile { inherit name text; };
        shellScriptBin =
          name: text:
          shellFile {
            inherit name text;
            bin = true;
          };

        zshApp =
          { name, text }:
          final.writeTextFile {
            inherit name;
            executable = true;
            destination = "/bin/${name}";
            text = ''
              #!${lib.getExe final.zsh}
              ${text}'';
            checkPhase = ''
              ${lib.getExe final.zsh} -n "$target"
            '';
            meta.mainProgram = name;
          };

        hasNvidia = builtins.pathExists (/. + "/proc/driver/nvidia/version");

        # nixGLNvidia only exists when the overlay's eval-time detection worked;
        # builtins.readFile returns "" on kernels reporting /proc as zero-sized.
        # The `auto` set copies the file in a runCommand and always detects.
        nixGL =
          if final.stubbe.hasNvidia then
            (final.nixgl.nixGLNvidia or final.nixgl.auto.nixGLNvidia)
          else
            final.nixgl.nixGLIntel;

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
        };

        # nixGL's NVIDIA bundle ships no external EGL platform libs, so Nix-built
        # Wayland clients fail with "provided display handle is not supported".
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
