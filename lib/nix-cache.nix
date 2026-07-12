{
  substituters = [
    # First-party closures for THIS flake (stubbe HM + NixOS), so `hm switch`
    # substitutes the heavy first-party builds (phpantom_lsp, hyprland, wayle,
    # rust nightly, …) instead of compiling them locally. Pushed by whichever
    # machine compiled them (see bin/hm). Xilo ≥1.0 namespaces caches, so the
    # URL is /c/<namespace>/<cache>; ours all live in the `default` namespace.
    "https://nix.stubbe.dev/c/default/default"
    "https://nix.stubbe.dev/c/default/wayle"
    "https://nix.stubbe.dev/c/default/treeman"
    "https://nix.stubbe.dev/c/default/srv"
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "default:6uWvXutL9cXjV3lii+Ur5ff+ArQoG4kMBKNXWrIxhHg="
    "wayle:BA9vQHJFl0dx4Zl5y0tbk+Osfly7y6k6tPKWAy49rdQ="
    "treeman:nOhvFetrH3t/RtM5sPG1fYuX4dFjhbzrttIOVGJpPDI="
    "srv:FfS/3wZKXdWv2JB+w2d5rlwRhKOYEyxFROsQGIs6etk="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
