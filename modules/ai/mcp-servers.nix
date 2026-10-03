# Everything except notmuch is registered per repo (.mcp.json): these are
# stdio commands — one process per client session, resolved off PATH. No
# ports, no shared instances, no systemd units.
{ inputs, ... }:
{
  flake.modules.homeManager.mcpServers =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      inherit (config.home) homeDirectory;

      pkg = input: inputs.${input}.packages.${system}.default;

      enableMail = config.features.desktop;

      # `repoScoped` entries are kept out of the global client sets: a repo
      # that wants one lists it in .mcp.json, whose bare command resolves off
      # PATH — every binary below rides in home.packages.
      mkStdio = name: extraArgs: {
        command = "${pkg name}/bin/${name}";
        args = [
          "--config"
          "${homeDirectory}/.config/${name}/config.json"
        ]
        ++ extraArgs;
        repoScoped = true;
      };

      stdioServers = {
        atlassian-mcp = mkStdio "atlassian-mcp" [ ];
        jenkins-mcp = mkStdio "jenkins-mcp" [ ];
        sentry-mcp = mkStdio "sentry-mcp" [ ];
        ds = mkStdio "ds-mcp" [
          "serve"
          "--read-only"
        ];
        nix-mcp = {
          command = "${pkg "nix-mcp"}/bin/nix-mcp";
          args = [ ];
          repoScoped = true;
        };
      }
      // lib.optionalAttrs enableMail {
        # The one global server: mail is useful from every session.
        notmuch-mcp = {
          command = "${pkg "notmuch-mcp"}/bin/notmuch-mcp";
          args = [ ];
        };
      };

    in
    {
      options.stubbe.mcp.servers = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        description = "MCP server inventory: stdio commands, split only by repoScoped.";
      };

      config = {
        stubbe.mcp.servers = {
          inherit stdioServers;
        };

        home.packages =
          map pkg [
            "atlassian-mcp"
            "jenkins-mcp"
            "sentry-mcp"
            "ds-mcp"
            "nix-mcp"
          ]
          ++ lib.optional enableMail (pkg "notmuch-mcp");
      };
    };
}
