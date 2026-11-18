{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # .mcp.json registers `phix mcp` as this repo's only MCP server; direnv
      # loads this shell so the binary is on PATH for it.
      devShells.default = pkgs.mkShellNoCC {
        packages = [ inputs.phix.packages.${system}.default ];
      };
    };
}
