{ config, pkgs, constants ? null, ... }:

''
  ACCOUNTS_CONF="${config.xdg.configHome}/aerc/accounts.conf"
  ACCOUNTS_SRC="${./../../../aerc/accounts.conf}"
  mkdir -p "${config.xdg.configHome}/aerc"
  if [[ ! -f "$ACCOUNTS_CONF" ]] || ! cmp -s "$ACCOUNTS_SRC" "$ACCOUNTS_CONF"; then
    ${pkgs.coreutils}/bin/install -m600 "$ACCOUNTS_SRC" "$ACCOUNTS_CONF"
  fi
''
