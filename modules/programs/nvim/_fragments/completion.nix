{ ... }:
{
  plugins.blink-cmp = {
    enable = true;
    settings = {
      completion = {
        documentation = {
          auto_show = true;
          auto_show_delay_ms = 500;
        };
      };
      signature = {
        enabled = true;
        window.show_documentation = false;
      };
      fuzzy = {
        sorts = [
          { __raw = ''
              function(a, b)
                if (a.client_name == nil or b.client_name == nil) or (a.client_name == b.client_name) then
                  return
                end
                return a.client_name == 'copilot'
              end
            '';
          }
          "score"
          "sort_text"
        ];
      };
      sources = {
        default = [
          "lsp"
          "buffer"
          "snippets"
          "path"
        ];
      };
    };
  };

  plugins.friendly-snippets.enable = true;
  plugins.lazydev.enable = true;
}
