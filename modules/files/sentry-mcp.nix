_: {
  flake.modules.homeManager.filesSentryMcp =
    {
      config,
      homeLib,
      ...
    }:
    {
      # secrets/sentry-mcp is the raw JSON config the @stubbedev/sentry-mcp
      # server reads at startup. Edit with: hm secret edit sentry-mcp
      sops.secrets.sentry_mcp = homeLib.mkBinarySecret {
        name = "sentry-mcp";
        path = "${config.home.homeDirectory}/.sentry-mcp.json";
      };
    };
}
