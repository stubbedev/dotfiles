_: {
  flake.modules.homeManager.cloud =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.features.ops {
      home.packages = with pkgs; [ hcloud ];

      # The secret holds the raw token with no trailing newline: it lands inside
      # a quoted TOML string, so a newline would break the parse.
      sops.secrets.hetzner = pkgs.stubbe.secret { name = "hetzner"; };
      sops.templates."hcloud-cli.toml" = {
        content = ''
          active_context = "default"

          [[contexts]]
            name = "default"
            token = "${config.sops.placeholder.hetzner}"
        '';
        path = "${config.xdg.configHome}/hcloud/cli.toml";
      };

      sops.secrets.godaddy = pkgs.stubbe.secret { name = "godaddy"; };
    };
}
