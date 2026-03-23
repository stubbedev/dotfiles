_: {
  flake.modules.homeManager.phpDevelopment =
    {
      pkgs,
      homeLib,
      lib,
      config,
      ...
    }:
    let
      php = pkgs.php84.buildEnv {
        extensions =
          { all, ... }:
          builtins.attrValues (
            removeAttrs all [
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
              "openswoole" # conflicts with swoole; exclude both to avoid duplicate symbols
              "xml" # statically compiled into PHP base; loading as shared ext causes duplicate warning
              "snuffleupagus" # security hardening module that requires a config file to be useful
            ]
          );
        extraConfig = ''
          memory_limit = 4G
          post_max_size = 2G
          upload_max_filesize = 2G
          max_input_time = 300
          max_execution_time = 300
        '';
      };
      phpFpmBin = pkgs.writeShellScriptBin "php-fpm" ''
        cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/php/php-fpm.conf"
        case " $* " in
          *" -y "*|*" --fpm-config "*) exec ${php}/bin/php-fpm "$@" ;;
          *) exec ${php}/bin/php-fpm -y "$cfg" "$@" ;;
        esac
      '';
      # Expose all php binaries except php-fpm (replaced by phpFpmBin wrapper above)
      phpBins = pkgs.symlinkJoin {
        name = "php-with-extensions-8.4.19";
        paths = [ php ];
        postBuild = "rm $out/bin/php-fpm";
      };
    in
    lib.mkIf config.features.php {
      home.packages = with pkgs; [
        # PHP 8.4 with all evaluable extensions and generous runtime limits
        phpBins
        phpFpmBin

        # PHP tools (CLI)
        mago
      ];
    };
}
