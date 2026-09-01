_: {
  flake.modules.homeManager.php =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      phpPackage = pkgs.php84;

      excludedExts = [
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
        "memprof" # ZTS not supported (memprof.c #error)
        # configure: "bufferevent_openssl_get_ssl not found in event_openssl"
        # against current nixpkgs libevent/openssl; drop until upstream fixes.
        "event"
      ];

      extraIni = ''
        memory_limit = 4G
        post_max_size = 2G
        upload_max_filesize = 2G
        max_input_time = 300
        max_execution_time = 300

        ; Performance defaults. xdebug stays loaded but inert (xdebug.mode=off)
        ; — set XDEBUG_MODE=debug,develop in the shell to turn it on per
        ; session. pcov same idea: loaded but inert until a coverage run
        ; passes -dpcov.enabled=1. opcache in CLI keeps validate_timestamps=1
        ; so source edits are picked up immediately.
        xdebug.mode = off
        pcov.enabled = 0
        opcache.enable_cli = 1
      '';

      # ONE php build serves CLI, FPM and FrankenPHP. phpPackageZts replicates
      # frankenphp's internal override *exactly* (pkgs/by-name/fr/frankenphp:
      # phpEmbedWithZts) so its re-override on our buildEnv is a genuine no-op
      phpPackageZts = phpPackage.override {
        embedSupport = true;
        ztsSupport = true;
        staticSupport = pkgs.stdenv.hostPlatform.isDarwin;
        zendSignalsSupport = false;
        zendMaxExecutionTimersSupport = pkgs.stdenv.hostPlatform.isLinux;
      };

      php = phpPackageZts.buildEnv {
        extensions = { all, ... }: builtins.attrValues (removeAttrs all excludedExts);
        extraConfig = extraIni;
      };

      # Deliberately NOT `frankenphp.override { inherit php; }`: that only
      # changes which php.ini the binary symlinks, yet rebuilds the whole Go
      # binary (plus a 300M+ go-modules fetch) on every nixpkgs bump. Since
      frankenphp =
        assert pkgs.frankenphp.php.unwrapped.drvPath == phpPackageZts.unwrapped.drvPath;
        pkgs.symlinkJoin {
          name = "frankenphp-${pkgs.frankenphp.version}";
          paths = [ pkgs.frankenphp ];
          nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
          postBuild = ''
            wrapProgram $out/bin/frankenphp --set PHP_INI_SCAN_DIR ${php}/lib
          '';
        };

      phpFpmBin = lib.hiPrio (
        pkgs.stubbe.shellScriptBin "php-fpm" ''
          exec ${php}/bin/php-fpm -y "''${XDG_CONFIG_HOME:-$HOME/.config}/php/php-fpm.conf" "$@"
        ''
      );

      composer = phpPackage.packages.composer.override { inherit php; };
    in
    lib.mkIf config.features.php {
      xdg.configFile."php/php-fpm.conf".source = pkgs.stubbe.gen.ini "php-fpm.conf" {
        global = {
          pid = "/tmp/php-fpm.pid";
          error_log = "/tmp/php-fpm.log";
          daemonize = "no";
        };
        www = {
          listen = "127.0.0.1:9000";
          pm = "dynamic";
          "pm.max_children" = 5;
          "pm.start_servers" = 2;
          "pm.min_spare_servers" = 1;
          "pm.max_spare_servers" = 3;
        };
      };

      home.packages = with pkgs; [
        php
        phpFpmBin
        frankenphp
        composer
        mago
        tesseract
        phpantom_lsp
      ];
    };
}
