{ inputs, ... }:
let
  # greetd's initial_session execs directly with only the PAM environment, so
  # the HM session vars have to be sourced here. HOME/USER come from passwd when
  # unset, or the profile lookups strand the session on a text tty.
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
      launcher = pkgs.writeShellScript "hyprland-greetd-session" greetdSessionScript;
    in
    lib.mkIf config.stubbe.userFeatures.hyprland {
      programs.hyprland.enable = true;

      # No graphical greeter: a Wayland-compositor greeter holds DRM master and
      # releases it too slowly when an external display is lit, so the incoming
      # session loses the handoff race and black-screens. Access is gated by
      # wayle-lock instead, so the session boots locked.
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${launcher}";
            user = config.host.primaryUser;
          };
          # agreety is not a compositor and never takes DRM master, so it
          # reintroduces no handoff race.
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

      # The live checkout, not the store, so an edit takes effect on the next
      # dispatch without a rebuild.
      scriptDir = "${config.stubbe.paths.dotfiles}/src/hyprland/scripts";

      # Nix's mesa-libgbm ships no GBM backends, so off-NixOS the binary cannot
      # find the host drivers. Collapses to a rename on NixOS.
      hyprlandWrapped = gfx.wrapAs "hyprland" pkgs.hyprland;

      # start-hyprland expects `Hyprland`; everything else prefers lowercase.
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

      # $HOME placeholders expand against the real home; the literal
      # $XDG_DATA_DIRS placeholder home-manager injects is dropped.
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

      # Without --no-nixgl the upstream watchdog wraps a second time.
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

      # Shells predating a Hyprland restart carry a stale
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

      compositorSession = pkgs.writeShellScriptBin "compositor-session" ''
        set -eu
        self="''${1:?compositor name required (hyprland)}"
        exec ${lib.getExe' pkgs.systemd "systemctl"} --user start "$self-session.target"
      '';

      # `.src`, not the built package: the generator and the headers it parses
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
        (gfx.wrapExe "Xwayland" pkgs.xwayland)
        (gfx.wrapExe "hyprland-guiutils"
          inputs.hyprland-guiutils.packages.${pkgs.stdenv.hostPlatform.system}.default
        )
        (gfx.wrap pkgs.hyprpicker)
        (gfx.wrap pkgs.cage)
        (pkgs.runCommandLocal "monitor-brightness" { } ''
          install -Dm755 ${pkgs.stubbe.file "src/hyprland/scripts/monitor.brightness.sh"} $out/bin/monitor-brightness
        '')
      ]
      ++ (with pkgs; [
        hypridle
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
        wtype
        socat
        # libnotify CLI callers silently no-op without the binary on PATH.
        libnotify
        xdg-desktop-portal
      ]);

      xdg.configFile = {
        "hypr/hyprland.lua".source = pkgs.stubbe.file "src/hyprland/hyprland.lua";
        "hypr/.luarc.json".source = pkgs.stubbe.file "src/hyprland/.luarc.json";
        "hypr/hypridle.conf".source = pkgs.stubbe.file "src/hyprland/hypridle.conf";
        "hypr/scripts".source = pkgs.stubbe.file "src/hyprland/scripts";

        "hypr/hl.meta.lua".source = hlMetaStub;

        # hy3 ships no stubs, so these are hand-written and can go stale.
        "hypr/hy3.meta.lua".source = pkgs.stubbe.file "src/hyprland/hy3.meta.lua";

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
          # xdg-desktop-portal 1.22+ has Requisite=graphical-session.target but
          # never starts it, so without this bind the portal fails instantly.
          BindsTo = [ "graphical-session.target" ];
          Before = [ "graphical-session.target" ];
        };

        services = {
          # A unit, not exec-once: a crash would otherwise leave the session
          # suspending unlocked, and exec-once keeps the old config until the
          # next login.
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

          # Runs from the live checkout, so a restart picks up script edits.
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

          # hyprpolkitagent ships only $out/libexec, no bin entry, so
          # home-manager's bin-only linking cannot surface it.
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
        # Auto-reload is off in hyprland.lua: reloading with multiple monitors
        # re-attaches workspaces and shifts focus. Doing it here lets the focused
        # workspace be captured first and restored after.
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

                  # Capture and restore, or a multi-monitor reload shifts focus.
                  before=$(${hyprctl} monitors -j 2>/dev/null) || exit 0
                  focused_ws=$(printf '%s' "$before" \
                    | jq -r 'map(select(.focused == true))[0].activeWorkspace.id // empty')
                  per_monitor=$(printf '%s' "$before" \
                    | jq -r '.[] | "\(.name) \(.activeWorkspace.id)"')

                  ${hyprctl} reload >/dev/null 2>&1 || exit 0

                  # Reload re-enables eDP-1, so the lid-closed layout has to be
                  # re-applied before workspace restore or workspaces migrate back.
                  # `hyprctl keyword` is rejected under the Lua config, hence eval.
                  if grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
                    ${hyprctl} eval "reflow_monitors(true)" >/dev/null 2>&1 || true
                  fi

                  # Legacy `hyprctl dispatch <name> <args>` is parsed as Lua under the
                  # Lua config, so pass a dispatcher expression instead.
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
              # Installed to /etc rather than referenced as a store path, so
              # nix-collect-garbage can never remove the file login depends on.
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

              # Debian's package usually creates this user; other distros do not.
              if ! getent passwd greeter >/dev/null 2>&1; then
                sudo useradd --system --create-home --home-dir /var/lib/greetd \
                  --shell /usr/sbin/nologin --user-group \
                  --groups video,input greeter 2>/dev/null || true
              fi

              ${pkgs.stubbe.installText {
                name = "hyprland-session.sh";
                target = launcher;
                mode = "0755";
                # Host /bin/sh, not a store path: login runs this and it must
                # survive a nix-collect-garbage.
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

              # Ubuntu does not pull plymouth-quit-wait into the boot transaction,
              # so `plymouth quit` runs concurrently with greetd and its VT restore
              # yanks the console back to tty1. greetd then waits forever for its
              # VT and autologin never fires.
              ${pkgs.stubbe.installText {
                name = "greetd-plymouth-order.conf";
                target = "/etc/systemd/system/greetd.service.d/plymouth-order.conf";
                text = ''
                  # Managed by stubbe — modules/hyprland.nix
                  [Unit]
                  After=plymouth-quit.service plymouth-quit-wait.service
                '';
              }}
              sudo systemctl daemon-reload

              # Disable competing DMs first, so their display-manager.service alias
              # symlinks come down before greetd claims the name.
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
