_: {
  args =
    { pkgs, ... }:
    {
      actionScript = ''
        ${pkgs.bun}/bin/bun add --global oxlint oxfmt >/dev/null 2>&1
      '';
    };
}
