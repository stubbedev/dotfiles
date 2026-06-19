_: {
  flake.modules.nixos.sudo = _: {
    security.sudo = {
      # Explicit policy: wheel members must enter their password for
      # sudo. This is the upstream default; declared here so a future
      # module that pulls in passwordless-wheel as a side effect
      # (devshells, CI helpers, etc.) doesn't silently flip it off.
      wheelNeedsPassword = true;

      # Restrict the sudo binary's setuid bit to wheel members only.
      # Non-wheel users can't even invoke `sudo`, removing one rung of
      # privilege escalation surface. The primary user is in `wheel`
      # (modules/nixos/users.nix), so day-to-day sudo is unaffected.
      execWheelOnly = true;

      # Show '*' for each typed password character. Off by default
      # (sudo gives no echo at all). Note: reveals password length to
      # shoulder-surfers.
      extraConfig = ''
        Defaults pwfeedback
      '';
    };
  };
}
