_: {
  flake.modules.nixos.sudo =
    { ... }:
    {
      # Explicit policy: wheel members must enter their password for
      # sudo. This is the upstream default; declared here so a future
      # module that pulls in passwordless-wheel as a side effect
      # (devshells, CI helpers, etc.) doesn't silently flip it off.
      security.sudo.wheelNeedsPassword = true;
    };
}
