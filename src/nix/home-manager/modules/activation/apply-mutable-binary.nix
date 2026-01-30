{ ... }:
{
  flake.modules.homeManager.activation.customBinInstall =
    { pkgs, lib, ... }:
    {
      home.activation.customBinInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        set -euo pipefail

        echo "Installing opencode-ai globally..."
        "${pkgs.bun}/bin/bun" install opencode-ai@latest --global

        echo "Installing biome globally..."
        "${pkgs.bun}/bin/bun" install biome@latest --global

        "${pkgs.bun}/bin/bun" pm trust --all || true

        echo "Installing lazydocker globally..."
        "${pkgs.go}/bin/go" install github.com/jesseduffield/lazydocker@latest
      '';
    };
}
