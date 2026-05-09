{ pkgs, lib, ... }:
{
  plugins.conform-nvim = {
    enable = true;
    settings = {
      formatters_by_ft = {
        html = [ "prettier" ];
        xml = [ "prettier" ];
        markdown = [ "prettier" ];
        vue = [ "prettier" ];
        php = [ "pint" ];
        caddy = [ "caddy" ];
        lua = [ "stylua" ];
      };
      formatters = {
        prettier = {
          command = lib.getExe pkgs.prettier;
        };
        caddy = {
          command = lib.getExe pkgs.caddy;
          args = [
            "fmt"
            "-"
          ];
          stdin = true;
        };
        stylua = {
          command = lib.getExe pkgs.stylua;
        };
      };
    };
  };

  extraFiles."stylua.toml".text = ''
    indent_type = "Spaces"
    indent_width = 2
    column_width = 120
  '';
}
