{ pkgs, ... }:
{
  gtk = {
    enable = true;
    
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    
    iconTheme = {
      name = "Vimix-dark";
      package = pkgs.vimix-icon-theme;
    };
    
    cursorTheme = {
      name = "Vimix-cursors";
      package = pkgs.vimix-cursors;
      size = 24;
    };
    
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
  };
}
