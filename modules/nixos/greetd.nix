{ self, ... }:
{
  # Login on NixOS: greetd with autologin straight into Hyprland — no
  # interactive greeter at boot. This replaces the old wayle-greeter
  # (cage-hosted GTK greeter) configured via programs.wayle.greeter, which is
  # no longer enabled in modules/nixos/wayle.nix.
  #
  # Why autologin + no graphical greeter: a Wayland-compositor greeter (the old
  # SDDM/kwin path on the Ubuntu host, or cage here) holds DRM master and tears
  # it down slowly when an external display is lit, so the incoming session
  # loses the DRM-master handoff race and black-screens. greetd's initial_session
  # runs the session directly with nothing holding DRM master ahead of it, so the
  # race cannot happen. The access gate is wayle-lock, launched at Hyprland start
  # (src/hypr/hyprland.lua) — the session boots to a locked screen.
  #
  # Kept in sync with the standalone-HM path in
  # modules/activation/_privileged/setup-greetd.nix (same launcher, same shape).
  flake.modules.nixos.greetd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmFeatures = config.home-manager.users.${config.host.primaryUser}.features or { };
      # Shared launcher: loads the user's HM session env, then execs
      # start-hyprland. See src/greetd/hyprland-session.sh.
      launcher = pkgs.writeShellScript "hyprland-greetd-session" (
        builtins.readFile (self + "/src/greetd/hyprland-session.sh")
      );
    in
    lib.mkIf (hmFeatures.hyprland or false) {
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${launcher}";
            user = config.host.primaryUser;
          };
          # Fallback shown only after an explicit logout: agreety, a minimal
          # text prompt. It is not a compositor and never takes DRM master, so
          # it reintroduces no handoff race. Runs as the greetd `greeter` user.
          default_session.command = "${lib.getExe' pkgs.greetd.greetd "agreety"} --cmd ${launcher}";
        };
      };
    };
}
