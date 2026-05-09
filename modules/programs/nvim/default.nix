_: {
  flake.modules.homeManager.programsNvim =
    {
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      programs.nixvim = {
        enable = true;
        imports = [
          ./_fragments/core.nix
          ./_fragments/lazyvim-defaults.nix
          ./_fragments/lsp.nix
          ./_fragments/formatters.nix
          ./_fragments/treesitter.nix
          ./_fragments/plugins-core.nix
          ./_fragments/completion.nix
          ./_fragments/languages.nix
          ./_fragments/dap-test.nix
          ./_fragments/ai.nix
          ./_fragments/utility.nix
        ];
      };
    };
}
