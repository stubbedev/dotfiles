{
  self,
  lib,
  config,
  nixpkgsFor,
  ...
}:
let
  hosts = config.configurations.nixOnDroid;

  xiloStore = config.stubbe.lib.cache.xilo.store;

  build =
    name:
    let
      inherit (self.nixOnDroidConfigurations.${name}.config) nix;
    in
    ''
      installable=".#nixOnDroidConfigurations.${name}.activationPackage"
      if nix path-info --store ${lib.escapeShellArg xiloStore} "$(nix eval --raw --impure "$installable.outPath")" > /dev/null 2>&1; then
        echo "${name}: closure already in ${xiloStore}"
      else
        nix build "$installable" \
          --impure --no-link --print-build-logs \
          --extra-substituters ${lib.escapeShellArg (toString nix.substituters)} \
          --extra-trusted-public-keys ${lib.escapeShellArg (toString nix.trustedPublicKeys)}
      fi
    '';

  buildAndroid =
    system:
    let
      pkgs = nixpkgsFor system;
    in
    {
      type = "app";
      program = lib.getExe (
        pkgs.stubbe.bashApp {
          name = "build-android";
          runtimeInputs = [
            pkgs.nix
            pkgs.git
          ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            ${lib.concatMapStrings build (
              lib.attrNames (lib.filterAttrs (_: host: host.system == system) hosts)
            )}
          '';
        }
      );
    };
in
{
  flake.apps = lib.genAttrs (lib.unique (lib.mapAttrsToList (_: host: host.system) hosts)) (system: {
    build-android = buildAndroid system;
  });
}
