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
      # phpPackage   — switch the major version here (e.g. pkgs.php83).
      # excludedExts — broken / proprietary / conflicting / non-ZTS; excluded
      #                everywhere. One build serves CLI, FPM and FrankenPHP,
      #                so anything that can't ride ZTS lands here.
      # extraIni     — runtime limits applied to every SAPI.
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

      # === Builders =========================================================
      # ONE php build serves CLI, FPM and FrankenPHP. phpPackageZts replicates
      # frankenphp's internal override *exactly* (pkgs/by-name/fr/frankenphp:
      # phpEmbedWithZts) so its re-override on our buildEnv is a genuine no-op
      # — buildEnv preserves the extension list and the override chain
      # (mkBuildEnv uses lib.makeOverridable), so frankenphp ends up embedding
      # the very same store path we put on PATH. Diverge on any of these args
      # and nix silently compiles a second php.
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

      # The assert is the whole point: frankenphp re-overrides whatever php it
      # is handed, so if nixpkgs adds or changes an arg in phpEmbedWithZts,
      # phpPackageZts above stops matching and nix quietly compiles a second
      # php. Comparing what frankenphp actually embeds against what we PATH
      # turns that into an eval failure the flake checks catch.
      frankenphp =
        let
          fp = pkgs.frankenphp.override { inherit php; };
        in
        assert fp.php.drvPath == php.drvPath;
        fp;

      # php-fpm wrapper so `php-fpm` defaults to ~/.config/php/php-fpm.conf
      # without forcing the user to pass -y every invocation. An explicit
      # -y / --fpm-config still wins: php-fpm takes the *last* one given.
      # hiPrio resolves the bin/php-fpm collision with php's own copy.
      phpFpmBin = lib.hiPrio (
        pkgs.writeShellScriptBin "php-fpm" ''
          exec ${php}/bin/php-fpm -y "''${XDG_CONFIG_HOME:-$HOME/.config}/php/php-fpm.conf" "$@"
        ''
      );

      # Composer pinned to our extension-laden php so `composer install`
      # uses the same SAPI/extension set as the user's `php` invocations.
      composer = phpPackage.packages.composer.override { inherit php; };
    in
    lib.mkIf config.features.php {
      home.packages = with pkgs; [
        # `php` on PATH is literally frankenphp's embedded interpreter — same
        # store path, one build. Kept as the real CLI SAPI rather than a
        # `frankenphp php-cli` shim: php-cli takes only `script.php [args]`
        # and `-r`, and chokes on -d/-v/-m/-i/-a/stdin.
        php
        phpFpmBin
        frankenphp
        composer
        mago
        # OCR engine for PHP tesseract wrappers (thiagoalessio/tesseract_ocr
        # et al). No maintained native PHP extension exists; the composer
        # packages shell out to this binary, so PATH covers both php-fpm/CLI
        # and frankenphp.
        tesseract
        # PHP language server. On global PATH so Claude Code's phpantom-lsp
        # plugin (src/claude/phpantom-lsp) and any non-nvim consumer find it;
        # nvim gets its own copy via the wrapper's runtimePkgs.
        phpantom_lsp
      ];
    };
}
