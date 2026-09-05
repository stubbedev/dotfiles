#!/usr/bin/env bash
# Decrypt the butane config and transpile it to ignition.json.
# The plaintext butane is never written to disk — it is piped straight
# from sops into butane.
set -euo pipefail
cd "$(dirname "$0")/.."
sops --decrypt --input-type binary --output-type binary secrets/flatcar-server.bu \
  | nix run nixpkgs#butane -- --strict \
  > flatcar/ignition.json
echo "wrote flatcar/ignition.json"
