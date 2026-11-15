_: {
  flake.modules.homeManager.setup =
    { config, lib, ... }:
    {
      options.stubbe.setup = lib.mkOption {
        description = "Activation-time shell steps, keyed by DAG node name.";
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to run this step. Gate it on a `features.*` flag.";
              };

              script = lib.mkOption {
                type = lib.types.lines;
                description = ''
                  The shell to run. Idempotent, please — it runs on every
                  switch. Activations run with a stripped PATH.
                '';
              };

              after = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Extra home-manager activation DAG nodes to order after.";
              };
            };
          }
        );
      };

      config.home.activation = lib.mapAttrs (
        _: setup: lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ setup.after) setup.script
      ) (lib.filterAttrs (_: s: s.enable) config.stubbe.setup);
    };
}
