_: {
  flake.modules.nixos.sudo =
    { ... }:
    {
      # Explicit policy: wheel members must enter their password for
      # sudo. This is the upstream default; declared here so a future
      # module that pulls in passwordless-wheel as a side effect
      # (devshells, CI helpers, etc.) doesn't silently flip it off.
      security.sudo.wheelNeedsPassword = true;

      # Restrict the sudo binary's setuid bit to wheel members only.
      # Non-wheel users can't even invoke `sudo`, removing one rung of
      # privilege escalation surface. The primary user is in `wheel`
      # (modules/nixos/users.nix), so day-to-day sudo is unaffected.
      security.sudo.execWheelOnly = true;
    };
}
