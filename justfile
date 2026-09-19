# Autofix what the linters can fix (statix, deadnix, nixfmt).
lint-fix:
    nix run .#lint-fix

# Full check set. --impure: modules/graphics.nix reads /proc for GPU
# detection and throws under pure eval. Hard-capped so nothing can wedge the
# run: checks bound their own scripts via pkgs.stubbe.check, this is the
# backstop for everything around them.
check:
    timeout 2700 nix flake check --impure
