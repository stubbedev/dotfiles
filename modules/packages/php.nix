_: {
  flake.modules.homeManager.phpDevelopment =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # === Knobs ============================================================
      # phpPackage         — switch the major version here (e.g. pkgs.php83).
      # sharedExcludedExts — broken / proprietary / conflicting; excluded
      #                      everywhere.
      # phpExcludedExts    — extensions excluded from the CLI/FPM build.
      # frankenphpExcludedExts — extensions excluded from the FrankenPHP build
      #                          (ZTS, embedded SAPI). Anything that doesn't
      #                          support ZTS lands here.
      # extraIni           — runtime limits applied to every SAPI.
      phpPackage = pkgs.php84;

      sharedExcludedExts = [
        "blackfire" # proprietary, requires license
        "couchbase" # broken
        "datadog_trace" # broken
        "ioncube-loader" # proprietary loader
        "oci8" # requires Oracle client
        "openssl-legacy" # removed from nixpkgs
        "parallel" # broken
        "pdo_oci" # requires Oracle client
        "php-spx" # deprecated alias for spx
        "relay" # proprietary
        "tideways" # unsupported PHP version
        "swoole" # conflicts with openswoole (duplicate function names)
        "openswoole" # conflicts with swoole
        "xml" # statically compiled into PHP base; loading as shared ext warns
        "snuffleupagus" # security hardening; needs a config to be useful
      ];

      phpExcludedExts = sharedExcludedExts;

      frankenphpExcludedExts = sharedExcludedExts ++ [
        "memprof" # ZTS not supported (memprof.c #error)
      ];

      extraIni = ''
        memory_limit = 4G
        post_max_size = 2G
        upload_max_filesize = 2G
        max_input_time = 300
        max_execution_time = 300
      '';

      # === Builders =========================================================
      # buildEnv preserves both the chosen extensions and the override chain
      # (mkBuildEnv uses lib.makeOverridable), so frankenphp's internal
      # `php.override { embedSupport = true; ztsSupport = true; ... }` re-
      # applies on top of our extension-laden php without losing the list.
      pickExtensions =
        excluded:
        { all, ... }:
        builtins.attrValues (removeAttrs all excluded);

      php = phpPackage.buildEnv {
        extensions = pickExtensions phpExcludedExts;
        extraConfig = extraIni;
      };

      phpForFrankenphp = phpPackage.buildEnv {
        extensions = pickExtensions frankenphpExcludedExts;
        extraConfig = extraIni;
      };

      frankenphp = pkgs.frankenphp.override { php = phpForFrankenphp; };

      # php-fpm wrapper so `php-fpm` defaults to ~/.config/php/php-fpm.conf
      # without forcing the user to pass -y every invocation. Pass-through
      # for explicit -y / --fpm-config so debugging configs stays easy.
      phpFpmBin = pkgs.writeShellScriptBin "php-fpm" ''
        cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/php/php-fpm.conf"
        case " $* " in
          *" -y "*|*" --fpm-config "*) exec ${php}/bin/php-fpm "$@" ;;
          *) exec ${php}/bin/php-fpm -y "$cfg" "$@" ;;
        esac
      '';

      # Surface every php binary except php-fpm (replaced by phpFpmBin).
      phpBins = pkgs.symlinkJoin {
        name = "php-with-extensions-${phpPackage.version}";
        paths = [ php ];
        postBuild = "rm $out/bin/php-fpm";
      };
    in
    lib.mkIf config.features.php {
      home.packages = with pkgs; [
        phpBins
        phpFpmBin
        frankenphp
        mago
      ];
    };
}
