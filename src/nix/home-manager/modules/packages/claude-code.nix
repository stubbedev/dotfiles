_: {
  flake.modules.homeManager.packagesClaudeCode =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.claudeCode {
      home.packages = [ pkgs.claude-code ];
    };
}
