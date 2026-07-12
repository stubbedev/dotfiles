{
  substituters = [
    # All first-party closures (stubbe HM + NixOS, plus wayle/treeman/srv/…)
    # live in one xilo cache now — `default` in the `default` namespace, hence
    # /c/default/default. `hm switch` substitutes the heavy first-party builds
    # from here instead of compiling locally; whichever machine compiles a
    # path pushes it back (see bin/hm). Everything is signed by the single
    # `default:` key below.
    "https://nix.stubbe.dev/c/default/default"
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "default:6uWvXutL9cXjV3lii+Ur5ff+ArQoG4kMBKNXWrIxhHg="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
