{ inputs, ... }:
let
  # The PHP for CLI, FPM, composer and the interpreter FrankenPHP embeds. Named
  # once here because the overlay below and the module have to agree; the assert
  # next to the `frankenphp` binding proves they still do.
  phpAttr = "php85";
in
{
  # FrankenPHP compiles its PHP in, so nixpkgs' default (still 8.4) cannot be
  # re-pointed at the use site - the Go binary itself has to be rebuilt. As an
  # overlay rather than a local `override` so shell.nix's completion generator
  # reuses this build instead of pulling the 8.4 one (and its whole php closure)
  # from the cache.
  flake.overlays.frankenphp-php = final: prev: {
    frankenphp = prev.frankenphp.override { php = final.${phpAttr}; };
  };

  flake.modules.homeManager.php =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      phpPackage = pkgs.${phpAttr};

      excludedExts = [
        "blackfire" # proprietary, requires license
        "couchbase" # broken
        "datadog_trace" # broken
        "igbinary" # marked broken on PHP >= 8.5 in nixpkgs
        "ioncube-loader" # proprietary loader
        "memcache" # marked broken on PHP >= 8.5 in nixpkgs
        "oci8" # requires Oracle client
        "openssl-legacy" # removed from nixpkgs
        "parallel" # broken
        "pdo_oci" # requires Oracle client
        "pdo_sqlsrv" # marked broken on PHP >= 8.5 in nixpkgs
        "phalcon" # marked broken on PHP >= 8.5 in nixpkgs
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

      # nixpkgs pins the mongodb driver well behind upstream. `mongodb-php-src`
      # is the *unversioned* PECL URL, so it always resolves to the newest
      # release and `nix flake update mongodb-php-src` is the only thing that
      # moves it - no hash or version is written down here. The version is read
      # back off the tarball's own `mongodb-<ver>/` directory.
      #
      # Overridden on the extension set handed to buildEnv rather than via
      # `packageOverrides`, which the buildEnv passthru chain drops, so it still
      # builds against the ZTS php above.
      mongodbLatest =
        ext:
        ext.overrideAttrs (_: rec {
          version =
            let
              names = builtins.attrNames (builtins.readDir inputs.mongodb-php-src);
              dirs = builtins.filter (n: builtins.match "mongodb-[0-9].*" n != null) names;
            in
            assert lib.assertMsg (dirs != [ ]) "no mongodb-<version>/ dir in mongodb-php-src";
            lib.removePrefix "mongodb-" (builtins.head dirs);

          # buildPecl bakes `name` from its *argument* version, so overriding
          # `version` alone leaves a store path claiming the nixpkgs version.
          name = "php-mongodb-${version}";
          src = inputs.mongodb-php-src;

          # The PECL tarball unpacks to two top-level entries (mongodb-<ver>/
          # and package.xml), so nix's fetcher strips no component.
          sourceRoot = "source/mongodb-${version}";
        });

      php = phpPackageZts.buildEnv {
        extensions =
          { all, ... }:
          builtins.attrValues (removeAttrs all excludedExts // { mongodb = mongodbLatest all.mongodb; });
        extraConfig = extraIni;
      };

      # The php swap already happened in the overlay above; all that is left
      # here is pointing the binary at OUR ini dir (extensions + extraIni). A
      # wrapper rather than a second `.override`, which would only change the
      # ini symlink yet rebuild the whole Go binary (plus a 300M+ go-modules
      # fetch) a second time.
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
