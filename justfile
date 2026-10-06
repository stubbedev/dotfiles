# Autofix what the linters can fix (statix, deadnix, nixfmt).
lint-fix:
    nix run .#lint-fix

# Full check set. Pure eval: GPU detection is host-driven
# (host.graphicsNvidia), nothing reads /proc any more. Hard-capped so
# nothing can wedge the run: checks bound their own scripts via
# pkgs.stubbe.check, this is the backstop for everything around them.
# (The installer ISO build still needs --impure: it reads $HOME and
# $STB_ISO_SSH_KEYS at eval time, see modules/installer.nix.)
check:
    timeout 2700 nix flake check
