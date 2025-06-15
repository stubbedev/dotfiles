self: super: {
  vesktop = super.vesktop.overrideAttrs (old: {
    installPhase = ''
      ${old.installPhase}
      mv $out/bin/vesktop $out/bin/vesktop-real
      cat > $out/bin/vesktop <<EOF
      #!${super.stdenv.shell}
      exec $out/bin/vesktop-real --no-sandbox "\$@"
      EOF
      chmod +x $out/bin/vesktop
    '';
  });
}
