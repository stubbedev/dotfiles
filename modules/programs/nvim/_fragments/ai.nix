{ pkgs, ... }:
{
  plugins.copilot-lua.enable = true;

  extraPlugins = with pkgs.vimPlugins; [
    blink-copilot
  ];
}
