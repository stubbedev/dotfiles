{ pkgs, ... }:
{
  plugins.dap.enable = true;
  plugins.dap-ui.enable = true;
  plugins.dap-virtual-text.enable = true;
  plugins.dap-go.enable = true;
  plugins.dap-python.enable = true;

  plugins.neotest = {
    enable = true;
    adapters = {
      golang.enable = true;
      phpunit.enable = true;
      python.enable = true;
    };
  };

  plugins.overseer.enable = true;

  extraPlugins = with pkgs.vimPlugins; [
    one-small-step-for-vimkind
  ];
}
