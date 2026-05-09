{ pkgs, ... }:
{
  plugins.treesitter = {
    enable = true;
    settings = {
      auto_install = false;
      highlight.enable = true;
      indent.enable = true;
    };
    grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      bash
      blade
      c
      caddy
      css
      scss
      dockerfile
      go
      gomod
      gosum
      html
      javascript
      json
      lua
      luadoc
      markdown
      markdown_inline
      nix
      php
      php_only
      python
      query
      regex
      rust
      sql
      templ
      toml
      tsx
      typescript
      vim
      vimdoc
      vue
      yaml
    ];
  };

  plugins.treesitter-context.enable = true;
  plugins.treesitter-textobjects.enable = true;
  plugins.ts-autotag.enable = true;

  extraFiles = {
    "after/queries/injections.scm".source = ../_queries/injections.scm;
    "after/queries/blade/injections.scm".source = ../_queries/blade/injections.scm;
    "after/queries/blade/folds.scm".source = ../_queries/blade/folds.scm;
    "after/queries/blade/highlights.scm".source = ../_queries/blade/highlights.scm;
  };
}
