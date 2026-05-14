{ chromePath, firefoxPath }:
{
  # Canonical MCP server definitions. Consumed by:
  #   modules/activation/_non-privileged/setup-claude-code.nix (.claude.json)
  #   modules/activation/_non-privileged/setup-opencode.nix    (opencode.json)
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
      "--executable-path"
      chromePath
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
  logseq-mcp = {
    command = "uv";
    args = [
      "run"
      "--with"
      "mcp-logseq"
      "mcp-logseq"
    ];
    env = {
      LOGSEQ_API_TOKEN = "logseq";
      LOGSEQ_API_URL = "http://localhost:12315";
    };
  };
}
