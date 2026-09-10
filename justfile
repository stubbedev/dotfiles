# Autofix what the linters can fix (statix, deadnix, nixfmt).
lint-fix:
    nix run .#lint-fix

# Full check set. --impure: modules/graphics.nix reads /proc for GPU
# detection and throws under pure eval. Skips hyprland-config, which builds
# Hyprland from source (CI excludes it for the same reason).
check:
    nix flake check --impure
