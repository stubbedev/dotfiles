# Native xberg PHP extension (document intelligence, Rust / ext-php-rs).
# Upstream ships only NTS prebuilts via PIE, so it's built from source here:
# the same derivation yields the NTS (CLI/FPM) and ZTS (FrankenPHP) variants
# depending on which php lands in scope. ext-php-rs discovers the target PHP
# through the PHP / PHP_CONFIG env vars and flips its php_zts cfg from what
# php-config reports.
{
  lib,
  php,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  leptonica,
  tesseract,
}:

# xberg-tesseract's build.rs cmake-builds leptonica + tesseract from source
# zips it downloads at compile time (versions pinned in its build.rs). The
# sandbox has no network, so the sources are pre-seeded from nixpkgs — these
# asserts fire when a nixpkgs bump desyncs the versions; then update build.rs
# expectations or pin fetchFromGitHub sources here instead.
assert leptonica.version == "1.87.0";
assert tesseract.version == "5.5.2";

rustPlatform.buildRustPackage rec {
  pname = "php-xberg";
  version = "1.0.0-rc.29";

  src = fetchFromGitHub {
    owner = "xberg-io";
    repo = "xberg";
    tag = "v${version}";
    hash = "sha256-7N7vqmAxQuVpgKPA9jbi+cD8aXZ4GxnrDpNXw1x1d+g=";
  };

  cargoHash = "sha256-IshAfuUGqAXimDUnGPbzolitq0QT/mTsKG4+uaL9NVc=";

  buildAndTestSubdir = "crates/xberg-php";

  # On Linux the crate hardcodes xberg with its full ORT feature set in the
  # dependency declaration itself (ort-sys downloads ONNX Runtime binaries at
  # build time — impossible in the sandbox). Swap it for upstream's curated
  # pure-Rust profile ("windows-target", maintained exactly because Windows CI
  # has the same constraint); buildFeatures below re-add the pure extras.
  postPatch = ''
    sed -i '/^xberg = /s/features = \["full".*\]/features = ["windows-target"]/' \
      crates/xberg-php/Cargo.toml

    # build.rs downloads eng.traineddata into OUT_DIR unconditionally, but the
    # blob is only include_bytes!'d under bundle-tessdata-eng (off here).
    sed -i 's/if !eng_traineddata.exists()/if false/' \
      crates/xberg-tesseract/build.rs
  '';

  preBuild = ''
    export TESSERACT_RS_CACHE_DIR=$TMPDIR/xberg-tesseract-cache
    mkdir -p $TESSERACT_RS_CACHE_DIR/third_party
    cp -r --no-preserve=mode ${leptonica.src} $TESSERACT_RS_CACHE_DIR/third_party/leptonica
    cp -r --no-preserve=mode ${tesseract.src} $TESSERACT_RS_CACHE_DIR/third_party/tesseract
  '';

  # Upstream default set minus reranker / sparse-embeddings / late-interaction:
  # those pull ONNX Runtime (ort), which wants either a network download or a
  # system libonnxruntime at build time. The pure-Rust *-presets stay in.
  # ponytail: add ort-dynamic + pkgs.onnxruntime when someone actually needs
  # reranking/embedding inference from PHP.
  buildNoDefaultFeatures = true;
  buildFeatures = [
    "api"
    "api-types"
    "auto-rotate-types"
    "chunking-tokenizers"
    "diff"
    "embedding-presets"
    "heuristics"
    "html"
    "keywords-rake"
    "keywords-yake"
    "late-interaction-presets"
    "layout-types"
    "liter-llm"
    "markdown-footnotes"
    "ocr"
    "ocr-wasm"
    "office"
    "paddle-ocr-types"
    "pdf"
    "presets"
    "quality"
    "redaction"
    "reranker-presets"
    "sparse-embedding-presets"
    "svg"
    "tokio-runtime"
    "transcription-types"
    "tree-sitter"
    "url-config-types"
    "url-ingestion"
    "xml"
  ];

  nativeBuildInputs = [
    rustPlatform.bindgenHook
    cmake
  ];
  dontUseCmakeConfigure = true;

  env = {
    PHP = "${php.unwrapped}/bin/php";
    PHP_CONFIG = "${php.unwrapped.dev}/bin/php-config";
    # tree-sitter-language-pack wants a parser-sources tarball from GitHub at
    # build time; offline mode skips it and grammars resolve via its runtime
    # download path instead. ponytail: seed TSLP_SOURCE_BUNDLE_URL=file://…
    # (bundle + .sha256) if offline code intelligence ever matters.
    TSLP_OFFLINE = "1";
  };

  # Tests exercise OCR/model paths that download at runtime.
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm644 target/*/release/libxberg_php.so $out/lib/php/extensions/xberg.so
    runHook postInstall
  '';

  passthru.extensionName = "xberg";

  meta = {
    description = "Xberg document intelligence PHP extension";
    homepage = "https://github.com/xberg-io/xberg";
    license = lib.licenses.mit;
  };
}
