# Idempotent activation-time operations on live dotfiles (~/.stubbe).
# Takes no dependencies today; kept as a function so every lib/ module
# is imported identically: `import ./lib/<name>.nix { deps }`. The
# throwaway parameter name satisfies statix (empty patterns are flagged).
_: {
  # Render an idempotent symlink-replacement snippet. Used in non-
  # privileged activations to point a config dir at the live src/ tree
  # in the dotfiles checkout, so edits are reflected without re-running
  # home-manager. mkdir -p covers the parent; rm -rf covers both stale
  # symlinks and previously-materialised directories.
  mkLiveSymlink =
    {
      config,
      src, # subpath under ~/.stubbe/src/
      target, # path under $HOME (no leading slash)
    }:
    let
      sourcePath = "${config.home.homeDirectory}/.stubbe/src/${src}";
      targetPath = "${config.home.homeDirectory}/${target}";
    in
    ''
      mkdir -p "$(dirname "${targetPath}")"
      rm -rf "${targetPath}"
      ln -s "${sourcePath}" "${targetPath}"
    '';

  # Copy a file from the live src/ tree to a target under $HOME. Use this
  # for config files that the owning app rewrites at runtime (btop.conf,
  # lazygit state.yml, …) — a symlink would be modified in place inside
  # the dotfiles checkout, which we don't want. The activation runs on
  # every switch, so the dotfiles version is authoritative on switch.
  mkLiveCopy =
    {
      config,
      src, # subpath under ~/.stubbe/src/
      target, # path under $HOME (no leading slash)
    }:
    let
      sourcePath = "${config.home.homeDirectory}/.stubbe/src/${src}";
      targetPath = "${config.home.homeDirectory}/${target}";
    in
    ''
      mkdir -p "$(dirname "${targetPath}")"
      cat "${sourcePath}" > "${targetPath}"
    '';
}
