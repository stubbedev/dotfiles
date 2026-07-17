#!/bin/sh
# greetd autologin session launcher — shared by NixOS (modules/nixos/greetd.nix)
# and standalone home-manager (modules/activation/_privileged/setup-greetd.nix).
#
# A display manager's wayland-session wrapper normally sources the user's login
# environment before starting the compositor. greetd's initial_session
# (autologin) execs its command directly with only the PAM environment, so we
# reproduce that here: pull in the Home-Manager session vars (PATH,
# XDG_DATA_DIRS, XCURSOR_*, MOZ_ENABLE_WAYLAND, ...) from whichever profile
# location this host uses, then hand off to the Hyprland launch wrapper.
#
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
