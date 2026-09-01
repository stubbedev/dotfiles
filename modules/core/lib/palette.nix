# Branch of the stubbe.lib trunk (see ../lib.nix).
# The single source of truth for colour and theme names; pkgs.stubbe.withHash
# and withArgb re-encode these for formats that want a different literal.
_: {
  stubbe.lib = {
    colors = {
      rosewater = "f5e0dc";
      flamingo = "f2cdcd";
      pink = "f5c2e7";
      mauve = "cba6f7";
      red = "f38ba8";
      maroon = "eba0ac";
      peach = "fab387";
      yellow = "f9e2af";
      green = "a6e3a1";
      teal = "94e2d5";
      sky = "89dceb";
      sapphire = "74c7ec";
      blue = "89b4fa";
      lavender = "b4befe";
      text = "cdd6f4";
      subtext1 = "bac2de";
      subtext0 = "a6adc8";
      overlay2 = "9399b2";
      overlay1 = "7f849c";
      overlay0 = "6c7086";
      surface2 = "585b70";
      surface1 = "45475a";
      surface0 = "313244";
      base = "1e1e2e";
      mantle = "181825";
      crust = "11111b";
    };

    theme = {
      icon = "Tela-circle-purple-dark";
      cursor = "Vimix-cursors";
      cursorSize = 24;
      gtk = "catppuccin-mocha-mauve-standard";
      kvantum = "Catppuccin-Mocha-Mauve";
      plymouth = "catppuccin-mocha";
    };

    # The page every new tab and the browser home button lands on.
    newtabUrl = "https://start.local/";
  };
}
