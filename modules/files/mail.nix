_: {
  flake.modules.homeManager.filesMail =
    {
      self,
      lib,
      config,
      homeLib,
      ...
    }:
    lib.mkIf config.features.desktop {
      # accounts.conf below references these paths via `cat`, so aerc reads
      # the password directly without a shell wrapper.
      sops.secrets.aerc-gmail = homeLib.mkBinarySecret {
        name = "aerc-gmail";
        path = "${config.home.homeDirectory}/.config/aerc/passwords/gmail";
      };
      sops.secrets.aerc-kontainer = homeLib.mkBinarySecret {
        name = "aerc-kontainer";
        path = "${config.home.homeDirectory}/.config/aerc/passwords/kontainer";
      };

      # open-mail / unsubscribe-mail / aerc-nvim-pager are built as Nix bins
      # in modules/home/scripts.nix and land under ~/.nix-profile/bin/.
      home.file.".w3m".source = self + "/src/w3m";

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
