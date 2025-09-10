# Package Organization

This directory contains packages organized into logical categories for better maintainability and understanding.

## Categories

### 🔧 **cli-core.nix** - Essential CLI Tools
Core command-line tools that form the foundation of the terminal experience.
- **Examples**: zsh, neovim, git, fzf, ripgrep
- **Priority**: High
- **Usage**: Always loaded

### 💻 **development.nix** - Development Tools  
Programming languages, IDEs, and development utilities.
- **Examples**: nodejs, rustup, jetbrains.phpstorm, mongodb-tools
- **Priority**: High
- **Usage**: Always loaded

### 🎨 **media.nix** - Media Processing
Image, video, and document processing tools.
- **Examples**: imagemagick, ffmpeg-full, libreoffice
- **Priority**: Medium
- **Usage**: Always loaded

### 🖥️ **applications.nix** - Desktop Applications
GUI applications that require nixGL wrapping for graphics acceleration.
- **Examples**: alacritty, mongodb-compass
- **Priority**: Medium
- **Usage**: Loaded when desktop features are enabled

### ⚙️ **system-services.nix** - System Services
Network management, bluetooth, and system-level utilities.
- **Examples**: networkmanager, blueman, clipman
- **Priority**: Low
- **Usage**: Loaded when desktop features are enabled

### 🎨 **theming.nix** - Desktop Theming
Fonts, icons, themes, and visual customization packages.
- **Examples**: rose-pine-gtk-theme, nerd-fonts.jetbrains-mono
- **Priority**: Low
- **Usage**: Loaded when desktop features are enabled

### 📦 **nix-tools.nix** - Nix Ecosystem
Nix-specific tools and system administration utilities.
- **Examples**: nh, lazydocker, pass
- **Priority**: Medium
- **Usage**: Always loaded

## Metadata

The `metadata.nix` file contains:
- Category descriptions and priorities
- Package loading order
- Conditional loading rules
- Example packages for each category

## Adding New Packages

1. **Identify the appropriate category** based on the package's primary function
2. **Add the package** to the relevant `.nix` file
3. **Add a comment** explaining the package's purpose if it's not obvious
4. **Update metadata.nix** if adding a new category or changing priorities

## Loading Order

Packages are loaded in priority order:
1. CLI Core Tools (high priority)
2. Development Tools (high priority)  
3. Nix Tools (medium priority)
4. Media Processing (medium priority)
5. Desktop Applications (medium priority, conditional)
6. System Services (low priority, conditional)
7. Desktop Theming (low priority, conditional)

## Conditional Loading

Some categories are only loaded when specific features are enabled:
- **Desktop-related packages** (applications, system-services, theming) are loaded when `features.desktop.enable` is true
- This allows for minimal server installations vs full desktop environments