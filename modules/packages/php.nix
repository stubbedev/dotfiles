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
      # buildEnv preserves both the chosen extensions and the override chain
      # (mkBuildEnv uses lib.makeOverridable), so frankenphp's internal
      # `php.override { embedSupport = true; ztsSupport = true; ... }` re-
      # applies on top of our extension-laden php without losing the list.
      pickExtensions =
        excluded:
        { all, ... }:
        builtins.attrValues (removeAttrs all excluded);

      # xberg (Rust/ext-php-rs, out-of-tree) can't ride the nixpkgs extension
      # set — php.override { packageOverrides = ... } silently drops the
      # overlay on the buildEnv passthru chain in current nixpkgs — so it's
      # built explicitly against each base php and appended per buildEnv.
      # ext-php-rs picks up ZTS from whatever php-config it's pointed at.
      mkXberg = basePhp: pkgs.callPackage ./_php-xberg.nix { php = basePhp; };

      # Pre-apply the exact override frankenphp does internally
      # (pkgs/by-name/fr/frankenphp: php.override { embedSupport; ztsSupport })
      # so its re-override is a no-op and our appended ZTS xberg stays
      # consistent with the php it's loaded into.
      phpPackageZts = phpPackage.override {
        embedSupport = true;
        ztsSupport = true;
      };

      php = phpPackage.buildEnv {
        extensions = args: pickExtensions phpExcludedExts args ++ [ (mkXberg phpPackage) ];
        extraConfig = extraIni;
      };

      phpForFrankenphp = phpPackageZts.buildEnv {
        extensions = args: pickExtensions frankenphpExcludedExts args ++ [ (mkXberg phpPackageZts) ];
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

      # Composer pinned to our extension-laden php so `composer install`
      # uses the same SAPI/extension set as the user's `php` invocations.
      composer = phpPackage.packages.composer.override { inherit php; };
    in
    lib.mkIf config.features.php {
      home.packages = with pkgs; [
        phpBins
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
