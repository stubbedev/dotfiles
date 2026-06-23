{
  substituters = [
    # Prebuilt toplevel closures for THIS flake (stubbe HM + NixOS), pushed
    # nightly by .github/workflows/prebuild.yml. Lets `hm switch` substitute
    # the heavy first-party builds (phpantom_lsp, hyprland, wayle, rust
    # nightly, …) instead of compiling them locally. See nix-cache repo.
    "https://nix.stubbe.dev/default"
    "https://nix.stubbe.dev/wayle"
    "https://nix.stubbe.dev/treeman"
    "https://nix.stubbe.dev/srv"
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "default:9P4FePqHV1rGv5NDBun0GN26y83pcaaMr/NHZrxKaac="
    "wayle:XD2O2h1Mmka+VegRi2JY7ywNbG9al+TUAZp6CObizFU="
    "treeman:wK3AZux2l7fX+L4Lo9OLh7zzQAC/OJDUQanldOgNhO4="
    "srv:zIqJz/1IhxGYhVu5uihWmWHyTSv6GPzCAk/6NCgrAMo="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
