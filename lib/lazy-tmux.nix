# lazy-tmux: tmux session snapshot/restore with scrollback and per-program
# integrations (a `claude` pane comes back as `claude --resume <id>`).
#
# Not in nixpkgs and upstream ships no flake, so pin the release tarball — a
# statically linked Go binary, nothing to compile. Bumping = new version + that
# release's sha256 from its checksums.txt; hm's bump_release_pins only rewrites
# `github:owner/repo/tag` flake inputs, so this pin is manual. x86_64-linux
# only, which is every host here.
#
# `_`-prefixed so import-tree skips it: this is a callPackage function, not a
# flake module. Consumed by modules/programs/tmux.nix (installs it) and
# modules/checks/tmux-session.nix (tests against it).
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lazy-tmux";
  version = "0.2.1";

  src = fetchurl {
    url = "https://github.com/alchemmist/lazy-tmux/releases/download/v${finalAttrs.version}/lazy-tmux_linux_amd64.tar.gz";
    sha256 = "ec3d100fd5d297f2f91660977692c24f238896ae265999b32aede8fd1e91c2fa";
  };

  # Tarball has no top-level directory (bin, LICENSE, README side by side).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 lazy-tmux $out/bin/lazy-tmux
    runHook postInstall
  '';

  meta = {
    description = "Lazy tmux session saver and restorer";
    homepage = "https://lazy-tmux.xyz";
    license = lib.licenses.mit;
    mainProgram = "lazy-tmux";
    platforms = [ "x86_64-linux" ];
  };
})
