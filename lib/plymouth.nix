{ pkgs }:
{
  # nixpkgs ships `catppuccin-plymouth` hardcoded to the macchiato flavor.
  # Upstream has all four — swap sourceRoot + install paths to package the
  # mocha variant, matching the Kvantum/GTK Catppuccin Mocha set. The sed
  # in installPhase patches ImageDir so plymouth finds the assets at its
  # final share/ path (matters on NixOS; the non-NixOS activation that
  # copies files into /usr/share also runs its own ImageDir sed for the
  # rewritten /usr path).
  catppuccinMochaPlymouth = pkgs.catppuccin-plymouth.overrideAttrs (_: {
    pname = "catppuccin-mocha-plymouth";
    sourceRoot = "source/themes/catppuccin-mocha";
    installPhase = ''
      runHook preInstall
      sed -i 's:\(^ImageDir=\)/usr:\1'"$out"':' catppuccin-mocha.plymouth
      mkdir -p $out/share/plymouth/themes/catppuccin-mocha
      cp * $out/share/plymouth/themes/catppuccin-mocha
      runHook postInstall
    '';
  });
}
