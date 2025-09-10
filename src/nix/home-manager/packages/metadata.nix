# Package metadata and organization
# Defines package categories, descriptions, and organizational structure
{ lib, ... }:

{
  # Package category definitions with descriptions
  categories = {
    cli-core = {
      name = "CLI Core Tools";
      description = "Essential command-line tools and shell utilities";
      priority = "high";
      examples = [ "zsh" "neovim" "git" "fzf" ];
    };

    development = {
      name = "Development Tools";
      description = "Programming languages, IDEs, and development utilities";
      priority = "high";
      examples = [ "nodejs" "rustup" "jetbrains.phpstorm" ];
    };

    media = {
      name = "Media Processing";
      description = "Image, video, and document processing tools";
      priority = "medium";
      examples = [ "imagemagick" "ffmpeg-full" "libreoffice" ];
    };

    applications = {
      name = "Desktop Applications";
      description = "GUI applications requiring nixGL wrapping";
      priority = "medium";
      examples = [ "alacritty" "mongodb-compass" ];
    };

    system-services = {
      name = "System Services";
      description = "Network management, bluetooth, and system utilities";
      priority = "low";
      examples = [ "networkmanager" "blueman" ];
    };

    theming = {
      name = "Desktop Theming";
      description = "Fonts, icons, themes, and visual customization";
      priority = "low";
      examples = [ "rose-pine-gtk-theme" "nerd-fonts.jetbrains-mono" ];
    };

    nix-tools = {
      name = "Nix Ecosystem";
      description = "Nix-specific tools and system administration utilities";
      priority = "medium";
      examples = [ "nh" "lazydocker" "pass" ];
    };
  };

  # Package loading order based on priority
  loadOrder = [
    "cli-core"
    "development"
    "nix-tools"
    "media"
    "applications"
    "system-services"
    "theming"
  ];

  # Conditional loading rules
  conditionalCategories = {
    theming = "desktop";
    applications = "desktop";
    system-services = "desktop";
  };
}

