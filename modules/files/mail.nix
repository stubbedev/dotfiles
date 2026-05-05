_: {
  flake.modules.homeManager.filesMail =
    {
      constants,
      self,
      lib,
      config,
      ...
    }:
    lib.mkIf config.features.desktop {
      # Decrypted at activation. accounts.conf below references these paths
      # via `cat`, so aerc reads the password directly without a wrapper.
      sops.secrets.aerc-gmail = {
        sopsFile = self + "/secrets/aerc-gmail";
        format = "binary";
        path = "${config.home.homeDirectory}/.config/aerc/passwords/gmail";
      };
      sops.secrets.aerc-kontainer = {
        sopsFile = self + "/secrets/aerc-kontainer";
        format = "binary";
        path = "${config.home.homeDirectory}/.config/aerc/passwords/kontainer";
      };

      home.file = {
        ".local/bin/open-mail" = {
          text = builtins.replaceStrings
            [ "@TERM@" ]
            [ constants.paths.term ]
            (builtins.readFile (self + "/src/_shared/scripts/open-mail"));
          executable = true;
        };
        ".local/bin/unsubscribe-mail".source = self + "/src/aerc/scripts/unsubscribe";
        ".local/bin/aerc-nvim-pager".source = self + "/src/aerc/scripts/nvim-pager.sh";
        ".w3m".source = self + "/src/w3m";
      };

      xdg.configFile."aerc/accounts.conf".text = ''
        [kontainer]
        source=imaps://abs@kontainer.com@ex.konformit.com:993
        source-cred-cmd=cat ${config.sops.secrets.aerc-kontainer.path}
        outgoing=smtp+login://abs@kontainer.com@ex.konformit.com:587
        outgoing-cred-cmd=cat ${config.sops.secrets.aerc-kontainer.path}
        cache-headers=true
        cache-max-age=720h
        default=INBOX
        from=abs@kontainer.com
        copy-to=Sent
        postpone=Drafts
        archive=Archive

        [gmail]
        source=imaps://alexander.bugge.stage@gmail.com@imap.gmail.com:993
        source-cred-cmd=cat ${config.sops.secrets.aerc-gmail.path}
        outgoing=smtp+plain://alexander.bugge.stage@gmail.com@smtp.gmail.com:587
        outgoing-cred-cmd=cat ${config.sops.secrets.aerc-gmail.path}
        cache-headers=true
        cache-max-age=720h
        default=INBOX
        from=alexander.bugge.stage@gmail.com
        copy-to=[Gmail]/Sent
        postpone=[Gmail]/Drafts
        archive=[Gmail]/All Mail
      '';
    };
}
