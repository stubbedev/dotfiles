{ firefoxPath }:
{
  # Canonical MCP server definitions. Consumed by:
  #   modules/activation/_non-privileged/setup-claude-code.nix (.claude.json)
  #
  # Caller passes absolute paths to chrome / firefox so the chrome-devtools
  # and firefox-devtools servers exec the same binaries the user launches
  # from the desktop.
  chrome-devtools = {
    command = "npx";
    args = [
      "-y"
      "chrome-devtools-mcp@latest"
      "--no-usage-statistics"
      "--auto-connect"
    ];
  };
  firefox-devtools = {
    command = "npx";
    args = [
      "-y"
      "firefox-devtools-mcp@latest"
      "--firefox-path"
      firefoxPath
    ];
  };
  atlassian-mcp = {
    command = "npx";
    args = [
      "-y"
      "@stubbedev/atlassian-mcp@latest"
    ];
  };
  sentry-mcp = {
    command = "npx";
    args = [
      "-y"
      "@stubbedev/sentry-mcp@latest"
    ];
  };
  jenkins-mcp = {
    command = "npx";
    args = [
      "-y"
      "@stubbedev/jenkins-mcp@latest"
    ];
  };
  nix-mcp = {
    command = "uvx";
    args = [ "mcp-nixos" ];
  };
  srv-mcp = {
    command = "srv";
    args = [ "mcp" ];
  };
  treeman-mcp = {
    command = "treeman";
    args = [ "mcp" ];
  };
  # ZenNotes vault tools. `zen` ships with the zennotes package
  # (modules/packages/system.nix); `zen mcp` is its stdio server. Vault is
  # resolved from ~/.config/ZenNotes (shared with the GUI) + $ZENNOTES_VAULT.
  zennotes-mcp = {
    command = "zen";
    args = [ "mcp" ];
  };
}
