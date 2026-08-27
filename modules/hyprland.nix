# Hyprland: the compositor, its Lua config, the session target everything else
# hangs off, and login (greetd autologin straight into it).
#
# The desktop SHELL — bar, notifications, OSD, wallpaper, lock — is wayle, in
# modules/wayle.nix. This file is only the compositor and its session.
{ inputs, ... }:
let
  # greetd autologin session launcher — shared by the NixOS half (a store
  # writeShellScript) and standalone home-manager (installed to
  # /etc/greetd/hyprland-session.sh, a real file so login survives GC).
  #
  # A display manager's wayland-session wrapper normally sources the user's
  # login environment before starting the compositor. greetd's initial_session
  # (autologin) execs its command directly with only the PAM environment, so we
  # reproduce that here: pull in the Home-Manager session vars (PATH,
  # XDG_DATA_DIRS, XCURSOR_*, MOZ_ENABLE_WAYLAND, ...) from whichever profile
  # location this host uses, then hand off to the Hyprland launch wrapper.
  #
  # greetd sets HOME/USER for the session, but the profile lookups below are
  # useless without them — derive from the passwd db if either is missing so a
  # thin session env can't silently strand us (no profile sourced →
  # start-hyprland not on PATH → exit → text tty).
  greetdSessionScript = ''
    [ -n "''${USER:-}" ] || USER="$(id -un)"
    [ -n "''${HOME:-}" ] || HOME="$(getent passwd "$USER" | cut -d: -f6)"
    export USER HOME

    # Both profile paths are probed so one script works on both platforms:
    #   ~/.nix-profile               — standalone home-manager (Ubuntu, ...)
    #   /etc/profiles/per-user/$USER — home-manager as a NixOS module
    for prof in "$HOME/.nix-profile" "/etc/profiles/per-user/$USER"; do
      if [ -r "$prof/etc/profile.d/hm-session-vars.sh" ]; then
        # shellcheck disable=SC1091  # runtime-only file, absent at lint time
        . "$prof/etc/profile.d/hm-session-vars.sh"
      fi
      case ":$PATH:" in
        *":$prof/bin:"*) ;;
        *) PATH="$prof/bin:$PATH" ;;
      esac
    done
    export PATH

    exec start-hyprland
  '';
in
{
  flake.modules.nixos.hyprland =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # The shared launcher: load the user's HM session env, then exec
      # start-hyprland. Same text the non-NixOS activation installs to /etc.
      launcher = pkgs.writeShellScript "hyprland-greetd-session" greetdSessionScript;
    in
    lib.mkIf config.stubbe.userFeatures.hyprland {
      # `package` defaults to pkgs.hyprland — the same one the HM wrappers wrap,
      # so both targets agree on the binary without pinning it here.
      programs.hyprland.enable = true;

      # Login: greetd with autologin straight into Hyprland, no interactive
      # greeter at boot.
      #
      # Why autologin and no graphical greeter: a Wayland-compositor greeter
      # (SDDM+kwin, or cage) holds DRM master and tears it down slowly when an
      # external display is lit, so the incoming session loses the DRM-master
      # handoff race and black-screens. greetd's initial_session runs the
      # session directly with nothing holding DRM master ahead of it, so the
      # race cannot happen. The access gate is wayle-lock, launched at Hyprland
      # start — the session boots to a locked screen.
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${launcher}";
            user = config.host.primaryUser;
          };
          # Shown only after an explicit logout: agreety, a minimal text
          # prompt. Not a compositor, never takes DRM master, so it
          # reintroduces no handoff race. Runs as the greetd `greeter` user.
          default_session.command = "${lib.getExe' config.services.greetd.package "agreety"} --cmd ${launcher}";
        };
      };
    };

  flake.modules.homeManager.hyprland =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stubbe) gfx;
      palette = pkgs.stubbe.colors;

      # Scripts live in the live checkout, not the store, so an edit takes
      # effect on the next dispatch without a rebuild. Also why the
      # monitor-toggle unit below can just be restarted.
      scriptDir = "${config.stubbe.paths.dotfiles}/src/hyprland/scripts";

      # nixGL-wrapped compositor. Nix's mesa-libgbm ships no GBM backends, so
      # off-NixOS the binary cannot find the host's drivers without this; on
      # NixOS the wrapper collapses to a rename.
      hyprlandWrapped = gfx.wrapAs "hyprland" pkgs.hyprland;

      # start-hyprland expects `Hyprland`; everything else here prefers
      # lowercase. Expose both names for the one binary.
      hyprlandBothCases = pkgs.linkFarm "hyprland-both-cases" [
        {
          name = "bin/hyprland";
          path = "${hyprlandWrapped}/bin/hyprland";
        }
        {
          name = "bin/Hyprland";
          path = "${hyprlandWrapped}/bin/hyprland";
        }
      ];

      # Resolve home.sessionPath / XDG_DATA_DIRS into ":"-joined absolute
      # strings for makeWrapper --prefix. $HOME placeholders expand against the
      # real home; the literal $XDG_DATA_DIRS placeholder home-manager injects
      # is dropped.
      sessionPaths =
        let
          replaceHome = lib.replaceStrings [ "$HOME" ] [ config.home.homeDirectory ];
          isPlaceholder = v: v == "$XDG_DATA_DIRS" || v == "\${XDG_DATA_DIRS}";
          rawDataDirs = lib.splitString ":" (config.home.sessionVariables.XDG_DATA_DIRS or "");
        in
        {
          path = lib.concatStringsSep ":" (map replaceHome config.home.sessionPath);
          dataDirs = lib.concatStringsSep ":" (
            map replaceHome (builtins.filter (v: v != "" && !isPlaceholder v) rawDataDirs)
          );
        };

      # --no-nixgl: the upstream watchdog's own nixGL detection would wrap a
      # second time. --path points it at our already-wrapped binary.
      startHyprland = pkgs.runCommand "start-hyprland" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        makeWrapper ${pkgs.hyprland}/bin/start-hyprland $out/bin/start-hyprland \
          --add-flags "--no-nixgl --path ${hyprlandWrapped}/bin/hyprland" \
          --prefix PATH : "${sessionPaths.path}" \
          --prefix PATH : "${
            lib.makeBinPath [
              hyprlandWrapped
              hyprlandBothCases
            ]
          }" \
          --prefix XDG_DATA_DIRS : "${sessionPaths.dataDirs}"
      '';

      # hyprctl with instance auto-detection. Shells started before a Hyprland
      # restart (tmux sessions, long-lived terminals) carry a stale
      # HYPRLAND_INSTANCE_SIGNATURE and every dispatch fails silently.
      hyprctl = pkgs.writeShellScriptBin "hyprctl" ''
        # Keep the existing signature when its socket is still live — always the
        # case when Hyprland itself dispatches an exec bind. Only auto-detect
        # when the variable is absent or points at a dead instance.
        uid="''${UID:-$(id -u)}"
        hypr_root="/run/user/$uid/hypr"

        _socket_ok() {
          [ -S "$hypr_root/$1/.socket.sock" ]
        }

        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && _socket_ok "$HYPRLAND_INSTANCE_SIGNATURE"; then
          : # already correct
        else
          # Newest instance (by lock file mtime) that has a live socket.
          current_instance=""
          newest_lock=""
          for lockfile in "$hypr_root"/*/hyprland.lock; do
            [ -e "$lockfile" ] || continue
            instance_name="''${lockfile%/hyprland.lock}"
            instance_name="''${instance_name##*/}"
            if _socket_ok "$instance_name"; then
              if [ -z "$newest_lock" ] || [ "$lockfile" -nt "$newest_lock" ]; then
                newest_lock="$lockfile"
                current_instance="$instance_name"
              fi
            fi
          done
          if [ -n "$current_instance" ]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$current_instance"
          fi
        fi

        exec ${pkgs.hyprland}/bin/hyprctl "$@"
      '';

      # Bring up the compositor's user systemd target, so everything
      # WantedBy=hyprland-session.target starts. Called from hyprland.lua.
      compositorSession = pkgs.writeShellScriptBin "compositor-session" ''
        set -eu
        self="''${1:?compositor name required (hyprland)}"
        exec ${lib.getExe' pkgs.systemd "systemctl"} --user start "$self-session.target"
      '';

      # LuaCATS type stubs for the `hl` API, generated from the exact Hyprland
      # source we run so they cannot drift from the running version. `.src`
      # rather than the built package: the generator and the headers it parses
      # only exist in the source tree.
      hlMetaStub = pkgs.runCommand "hl.meta.lua" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${pkgs.hyprland.src}/meta/generateLuaStubs.py --root ${pkgs.hyprland.src} --output "$out"
      '';

      sessionTarget = [ "hyprland-session.target" ];
    in
    lib.mkIf config.features.hyprland {
      home.packages = [
        hyprlandBothCases
        hyprctl
        startHyprland
        compositorSession
        # Replaces the Xwayland binary outright, so X11 apps get nixGL too.
        (gfx.wrapExe "Xwayland" pkgs.xwayland)
        (gfx.wrapExe "hyprland-guiutils"
          inputs.hyprland-guiutils.packages.${pkgs.stdenv.hostPlatform.system}.default
        )
        (gfx.wrap pkgs.hyprpicker)
        # Nested single-app Wayland compositor — for debugging screen-locking
        # and kiosk-style apps without locking the host session.
        (gfx.wrap pkgs.cage)
        # Brightness helper, also bound to XF86MonBrightness* in hyprland.lua
        # (which calls the script in the live checkout directly — the file
        # stays in src/hyprland/scripts/ with the rest of the live lua tree).
        (pkgs.runCommandLocal "monitor-brightness" { } ''
          install -Dm755 ${pkgs.stubbe.file "src/hyprland/scripts/monitor.brightness.sh"} $out/bin/monitor-brightness
        '')
      ]
      ++ (with pkgs; [
        # Idle daemon (ext-idle-notify-v1); the unit is below.
        hypridle
        # Polkit authentication agent; the unit is below.
        hyprpolkitagent
        hyprcursor
        hyprlang
        hyprkeys
        hyprtoolkit
        hyprlauncher
        hyprutils
        hyprprop
        hyprsysteminfo
        hyprwayland-scanner
        hyprpwcenter
        wayland-scanner
        wayland-utils
        wlprop
        wl-clipboard
        wl-clip-persist
        # The SUPER+V clipboard bind (hyprland.lua) ends with `wtype -M ctrl v`
        # to paste the picked entry back into the focused window.
        wtype
        # IPC glue for the scripts that talk to compositor/daemon sockets
        # (hy3 tiling, jetbrains popup resize, wayle widget helpers).
        socat
        # `notify-send` + libnotify. wayle owns
        # org.freedesktop.Notifications, but libnotify CLI callers silently
        # no-op without the binary on PATH.
        libnotify
        xdg-desktop-portal
      ]);

      xdg.configFile = {
        # Hyprland 0.55+ Lua config. It require()s the Nix-generated nix.lua
        # below for the values only Nix knows.
        "hypr/hyprland.lua".source = pkgs.stubbe.file "src/hyprland/hyprland.lua";
        "hypr/.luarc.json".source = pkgs.stubbe.file "src/hyprland/.luarc.json";
        # Ecosystem daemons still use hyprlang (no Lua support).
        "hypr/hypridle.conf".source = pkgs.stubbe.file "src/hyprland/hypridle.conf";
        "hypr/scripts".source = pkgs.stubbe.file "src/hyprland/scripts";

        # Generated `hl` API type stubs for lua_ls; .luarc.json points its
        # workspace.library here.
        "hypr/hl.meta.lua".source = hlMetaStub;

        # hy3 ships no stubs; hand-written from hy3 hl0.56.0.1 dispatchers.cpp.
        # Extends HL.PluginNamespace (from hl.meta.lua) with the hy3 factories.
        "hypr/hy3.meta.lua".source = pkgs.stubbe.file "src/hyprland/hy3.meta.lua";

        # hyprtoolkit theme (hyprpolkitagent and other hyprtoolkit GUIs),
        # 0xAARRGGBB, generated from the palette so it matches the rest.
        "hypr/hyprtoolkit.conf".text =
          let
            argb = pkgs.stubbe.withArgb;
          in
          ''
            # Catppuccin Mocha (Mauve), generated from pkgs.stubbe.colors.
            background=${argb.crust}
            base=${argb.base}
            alternate_base=${argb.mantle}
            text=${argb.text}
            bright_text=${argb.subtext1}
            accent=${argb.mauve}
            accent_secondary=${argb.lavender}
          '';

        # Nix-derived values require()d by hyprland.lua: cursor/NVIDIA env, the
        # hy3 plugin store path, the palette, and the live script dirs.
        "hypr/nix.lua".text = ''
          -- Generated by modules/hyprland.nix.
          -- Cursor — single source of truth: pkgs.stubbe.theme. Mirrored by HM
          -- home.sessionVariables and (on NixOS) environment.sessionVariables,
          -- but those do not propagate into Hyprland's process tree under a
          -- non-NixOS session manager, so set them via hl.env here too.
          hl.env("XCURSOR_THEME", "${pkgs.stubbe.theme.cursor}")
          hl.env("XCURSOR_SIZE", "${toString pkgs.stubbe.theme.cursorSize}")
          ${lib.optionalString pkgs.stubbe.hasNvidia ''
            hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
            hl.env("LIBVA_DRIVER_NAME", "nvidia")
            hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
            hl.env("NVD_BACKEND", "direct")
          ''}
          -- nixpkgs builds hy3 against pkgs.hyprland, the same compositor these
          -- wrappers run, so the plugin ABI cannot drift.
          hl.plugin.load("${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so")

          return {
            paths = { scripts = "${scriptDir}" },
            colors = {
              ${lib.concatStringsSep "\n    " (
                lib.mapAttrsToList (n: hex: ''${n} = "rgb(${hex})",'') palette
              )}
            },
          }
        '';
      };

      systemd.user = {
        targets.hyprland-session.Unit = {
          Description = "Hyprland session";
          # xdg-desktop-portal 1.22+ has Requisite=graphical-session.target,
          # which never starts the target itself — so without this bind the
          # portal fails instantly ("Dependency failed for Portal service").
          # BindsTo pulls graphical-session.target up with the session and drops
          # it on exit (that target is RefuseManualStart + StopWhenUnneeded).
          BindsTo = [ "graphical-session.target" ];
          Before = [ "graphical-session.target" ];
        };

        services = {
          # Idle lock, dpms, idle sleep, and the logind sleep delay-inhibitor
          # that runs before_sleep_cmd. A unit rather than exec-once so a crash
          # cannot silently leave the session suspending unlocked
          # (Restart=on-failure), and so sd-switch restarts it when
          # hypridle.conf changes — exec-once processes kept running the old
          # config until the next login.
          hypridle = {
            Unit = {
              Description = "Hypridle idle daemon (lock, dpms, idle sleep)";
              After = sessionTarget;
              PartOf = sessionTarget;
              X-Restart-Triggers = [ (toString config.xdg.configFile."hypr/hypridle.conf".source) ];
            };
            Install.WantedBy = sessionTarget;
            Service = {
              Type = "simple";
              # Listener commands (hyprctl, wayle-lock, loginctl) resolve via
              # PATH, and the systemd user manager's PATH has no nix profile.
              Environment = [ "PATH=${config.stubbe.paths.nixBin}:/usr/bin:/bin" ];
              ExecStart = lib.getExe pkgs.hypridle;
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };

          # DRM hotplug + lid reactor (monitors, wallpaper, wireplumber,
          # undock-while-closed suspend). Runs from the live checkout, so
          # `systemctl --user restart monitor-toggle` picks up script edits —
          # no relogin, no pkill hunting like the old exec-once launch.
          monitor-toggle = {
            Unit = {
              Description = "DRM hotplug + lid reactor (monitor.toggle.sh)";
              After = sessionTarget;
              PartOf = sessionTarget;
            };
            Install.WantedBy = sessionTarget;
            Service = {
              Type = "simple";
              Environment = [ "PATH=${config.stubbe.paths.nixBin}:/usr/bin:/bin" ];
              ExecStart = "${scriptDir}/monitor.toggle.sh daemon";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };

          # hyprpolkitagent ships only $out/libexec/hyprpolkitagent — no bin
          # entry — so home-manager's bin-only linking cannot surface it and
          # `systemctl --user start hyprpolkitagent` (called from hyprland.lua)
          # finds no unit. Defining it here also gives pkexec something to
          # talk to (nmcli, brightness, anything escalating interactively).
          hyprpolkitagent = {
            Unit = {
              Description = "Hyprland polkit authentication agent";
              After = sessionTarget;
              PartOf = sessionTarget;
            };
            Install.WantedBy = sessionTarget;
            Service = {
              Type = "simple";
              ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };
        };
      };

      stubbe.setup = {
        # Reload Hyprland after every successful switch when a live session is
        # detected; skipped silently otherwise (e.g. switching from a TTY) so it
        # never blocks activation.
        #
        # Hyprland's own config auto-reload is disabled via
        # misc.disable_autoreload in hyprland.lua, because reloading with
        # multiple monitors re-evaluates monitor rules and re-attaches
        # workspaces, which shifts focus. Doing it here lets us capture the
        # focused workspace first and dispatch back to it after.
        hyprlandReload.script =
          let
            # HM activation runs with a stripped PATH that excludes the user
            # profile, so hyprctl has to be named by absolute path.
            hyprctl = "${config.stubbe.paths.nixBin}/hyprctl";
          in
          lib.getExe (
            pkgs.stubbe.bashApp {
              name = "hyprland-reload";
              text = ''
                (
                  uid="''${UID:-$(id -u)}"
                  hypr_root="/run/user/$uid/hypr"

                  [ -d "$hypr_root" ] || exit 0

                  target_instance=""
                  if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && \
                     [ -S "$hypr_root/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
                    target_instance="$HYPRLAND_INSTANCE_SIGNATURE"
                  else
                    newest_mtime=0
                    for sock in "$hypr_root"/*/.socket.sock; do
                      [ -S "$sock" ] || continue
                      instance_dir="''${sock%/.socket.sock}"
                      instance="''${instance_dir##*/}"
                      mtime=$(stat -c %Y "$sock" 2>/dev/null || echo 0)
                      if [ "$mtime" -gt "$newest_mtime" ]; then
                        newest_mtime="$mtime"
                        target_instance="$instance"
                      fi
                    done
                  fi

                  [ -n "$target_instance" ] || exit 0

                  export HYPRLAND_INSTANCE_SIGNATURE="$target_instance"

                  # Capture (workspace, monitor) for every monitor + the globally focused
                  # workspace, reload, then restore so multi-monitor reloads don't shift
                  # focus.
                  before=$(${hyprctl} monitors -j 2>/dev/null) || exit 0
                  focused_ws=$(printf '%s' "$before" \
                    | jq -r 'map(select(.focused == true))[0].activeWorkspace.id // empty')
                  per_monitor=$(printf '%s' "$before" \
                    | jq -r '.[] | "\(.name) \(.activeWorkspace.id)"')

                  ${hyprctl} reload >/dev/null 2>&1 || exit 0

                  # Reload re-enables eDP-1 from monitors.conf and auto-positions the
                  # externals to its right; re-apply the lid-closed layout before
                  # workspace restore so workspaces don't migrate back. reflow_monitors
                  # disables eDP and re-packs the externals from 0,0 in one pass, so the
                  # external is not left stranded at a half-screen offset. (`hyprctl
                  # keyword` is rejected under the Lua config — "keyword can't work with
                  # non-legacy parsers. Use eval." — so drive it through the exposed Lua
                  # reflow_monitors instead.)
                  if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
                    ${hyprctl} eval "reflow_monitors(true)" >/dev/null 2>&1 || true
                  fi

                  # Legacy `hyprctl dispatch <name> <args>` is rejected under the Lua
                  # config (it is parsed as hl.dispatch(<args>) Lua); pass a Lua
                  # dispatcher expression instead. focusmonitor/workspace both map to
                  # hl.dsp.focus{ monitor = ... } / hl.dsp.focus{ workspace = ... }.
                  while IFS=' ' read -r mon ws; do
                    [ -n "$mon" ] && [ -n "$ws" ] || continue
                    ${hyprctl} dispatch "hl.dsp.focus({ monitor = '$mon' })" >/dev/null 2>&1 || true
                    ${hyprctl} dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1 || true
                  done <<<"$per_monitor"

                  if [ -n "$focused_ws" ]; then
                    ${hyprctl} dispatch "hl.dsp.focus({ workspace = $focused_ws })" >/dev/null 2>&1 || true
                  fi
                ) || true
              '';
            }
          );

        # Non-NixOS login: same launcher, same autologin + agreety-fallback
        # shape as services.greetd in the NixOS half.
        greetd = {
          privileged = true;
          title = "Installing greetd (autologin login manager, replaces SDDM)";
          body = ''
            Install greetd (which ships the agreety fallback greeter) via the
            host package manager, drop the shared Hyprland session launcher into
            /etc/greetd, write /etc/greetd/config.toml (autologin into Hyprland,
            agreety on logout), and make greetd the system display manager in
            place of SDDM.

            The display-manager swap disables any enabled DM (sddm/gdm/lightdm/…),
            repoints /etc/systemd/system/display-manager.service at
            greetd.service, and sets graphical.target as default. It does NOT
            restart the display manager — it takes effect on next reboot, so the
            current session survives.

            Recovery if autologin ever fails to render: switch to a text console
            (Ctrl+Alt+F3) and log in there to fix or roll back.
          '';
          script =
            let
              # greetd execs this at boot. Installed to /etc, NOT referenced as
              # a store path, so `nix-collect-garbage` can never remove the file
              # login depends on. It resolves start-hyprland at runtime from the
              # user's (GC-rooted) HM profile.
              launcher = "/etc/greetd/hyprland-session.sh";
            in
            ''
              PATH="/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

              ${pkgs.stubbe.installHostPackage {
                detect = "greetd";
                apt = [ "greetd" ];
                dnf = [ "greetd" ];
                pacman = [ "greetd" ];
              }}

              # Ensure the unprivileged `greeter` user greetd drops to for the
              # agreety fallback exists. Debian's package usually creates it;
              # idempotent here for other distros and partial installs.
              if ! getent passwd greeter >/dev/null 2>&1; then
                sudo useradd --system --create-home --home-dir /var/lib/greetd \
                  --shell /usr/sbin/nologin --user-group \
                  --groups video,input greeter 2>/dev/null || true
              fi

              ${pkgs.stubbe.installText {
                name = "hyprland-session.sh";
                target = launcher;
                mode = "0755";
                # Host /bin/sh, not a store path: this copy is what login runs,
                # and it must survive a nix-collect-garbage.
                text = "#!/bin/sh\n" + greetdSessionScript;
              }}

              ${pkgs.stubbe.installText {
                name = "greetd-config.toml";
                target = "/etc/greetd/config.toml";
                text = ''
                  # Managed by stubbe — modules/hyprland.nix
                  [terminal]
                  # VT 7: the Debian/Ubuntu greetd.service unit ships
                  # `Conflicts=getty@tty7`, so greetd must own tty7 or it
                  # collides with the un-conflicted getty@tty1 (both grab the
                  # VT, getty wins the console, autologin never renders →
                  # stranded on a text tty). tty1..6 stay as recovery consoles.
                  vt = 7

                  # Autologin: no interactive greeter at boot.
                  [initial_session]
                  command = "${launcher}"
                  user = "${config.home.username}"

                  # Fallback after an explicit logout: agreety text prompt (not
                  # a compositor, never takes DRM master).
                  [default_session]
                  command = "agreety --cmd ${launcher}"
                  user = "greeter"
                '';
              }}

              # Display-manager swap. Disable competing DMs FIRST so their
              # `[Install] Alias=display-manager.service` symlinks come down.
              current_dm=""
              if [ -L /etc/systemd/system/display-manager.service ]; then
                current_dm=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
              fi

              if [ "$current_dm" = "greetd" ]; then
                echo "greetd is already the default display manager; config refreshed." >&2
              else
                for dm in sddm gdm gdm3 lightdm lxdm xdm; do
                  if systemctl cat "$dm.service" >/dev/null 2>&1 \
                     && systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
                    echo "Disabling existing display manager: $dm" >&2
                    sudo systemctl disable "$dm.service" >/dev/null 2>&1 || true
                  fi
                done

                if [ -L /etc/systemd/system/display-manager.service ]; then
                  tgt=$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)
                  if [ "$tgt" != "greetd" ]; then
                    sudo rm -f /etc/systemd/system/display-manager.service
                  fi
                fi

                sudo systemctl enable greetd.service

                # Materialise the alias ourselves if greetd.service omits it.
                if [ ! -L /etc/systemd/system/display-manager.service ] \
                   || [ "$(basename "$(readlink /etc/systemd/system/display-manager.service)" .service)" != "greetd" ]; then
                  greetd_unit=$(systemctl show -p FragmentPath greetd.service --value 2>/dev/null)
                  if [ -n "$greetd_unit" ] && [ -e "$greetd_unit" ]; then
                    echo "Materialising display-manager.service → $greetd_unit." >&2
                    sudo rm -f /etc/systemd/system/display-manager.service
                    sudo ln -sf "$greetd_unit" /etc/systemd/system/display-manager.service
                  else
                    echo "ERROR: greetd.service has no readable FragmentPath. Display manager alias not set." >&2
                    exit 1
                  fi
                fi

                if command -v apt-get >/dev/null 2>&1 && [ -d /etc/X11 ]; then
                  greetd_bin=$(command -v greetd 2>/dev/null || echo /usr/bin/greetd)
                  echo "$greetd_bin" | sudo tee /etc/X11/default-display-manager >/dev/null
                fi

                if [ "$(sudo systemctl get-default 2>/dev/null)" != "graphical.target" ]; then
                  sudo systemctl set-default graphical.target >/dev/null
                fi

                echo "" >&2
                echo "greetd is now the default display manager (effective on next reboot)." >&2
                echo "Not restarting the display manager, to avoid killing the current session." >&2
              fi
            '';
        };
      };
    };
}
