{
  pkgs,
  inputs,
  ...
}:

{
  packages = [
    pkgs.git
    # Registered as this repo's only MCP server by .mcp.json; the devenv
    # shell puts the binary on PATH for it.
    inputs.nix-mcp.packages.${pkgs.stdenv.system}.default
  ];
}
