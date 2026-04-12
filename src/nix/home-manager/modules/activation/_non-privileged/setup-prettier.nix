_: {
  args =
    { pkgs, ... }:
    {
      actionScript = ''
        ${pkgs.bun}/bin/bun add --global prettier >/dev/null 2>&1
      '';
    };
}
