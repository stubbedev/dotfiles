# Branch of the stubbe.lib trunk (see ../lib.nix).
# The `hm` command catalogue: one declaration feeding the dispatcher, the
# completions and the help output.
{ lib, ... }:
{
  stubbe.lib = {
    hm =
      let
        cmd =
          {
            name,
            platform,
            group,
            desc,
            summary ? desc,
            syntax ? name,
            extra ? [ ],
            sub ? null,
            expand ? false,
            complete ? null,
          }:
          {
            inherit
              name
              platform
              group
              desc
              summary
              syntax
              extra
              sub
              expand
              complete
              ;
          };
        commands = map cmd [
          {
            name = "update";
            platform = "all";
            group = "wrapper";
            desc = "Update system package managers and nix inputs";
          }
          {
            name = "upgrade";
            platform = "all";
            group = "wrapper";
            desc = "Update system packages and apply switch (auto-prunes";
            extra = [ "old generations, keeping current + 1 previous)" ];
            summary = "Update system packages and apply switch";
          }
          {
            name = "whoami";
            platform = "all";
            group = "wrapper";
            desc = ''Print "<hostname> <age-pubkey>" for this machine'';
          }
          {
            name = "trust";
            syntax = "trust [name] <key>";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Add an age recipient to .sops.yaml and re-wrap secrets/*";
            summary = "Add an age recipient to .sops.yaml and re-wrap secrets/*";
            extra = [
              "- hm trust <name> <pubkey>"
              "- hm trust <pubkey>           (auto-named)"
              "- cmd | hm trust              (e.g. ssh other hm whoami | hm trust)"
            ];
          }
          {
            name = "secret";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            expand = true;
            desc = "Edit, set, or rotate an encrypted file under secrets/";
            sub = [
              {
                name = "edit";
                syntax = "edit <name>";
                desc = "Open secrets/<name> in $EDITOR via sops, binary mode (creates if absent)";
              }
              {
                name = "set";
                syntax = "set <name>";
                desc = "Replace secrets/<name> with a new value (prompts on TTY, reads stdin otherwise)";
              }
              {
                name = "rotate";
                syntax = "rotate <name>";
                desc = "Re-roll the data key for secrets/<name>, recipients unchanged";
              }
            ];
          }
          {
            name = "cache";
            syntax = "cache <target>";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Wipe cached state (target: nvim|locks|all)";
            sub = [
              {
                name = "nvim";
                desc = "Clear ~/.local/{share,state}/nvim and ~/.cache/nvim";
              }
              {
                name = "locks";
                desc = "Wipe ~/.local/state/nix/home-manager/*.lock.sum so every";
                extra = [ "privileged activation re-runs on next switch" ];
                summary = "Wipe ~/.local/state/nix/home-manager/*.lock.sum (re-runs every gated activation)";
              }
              {
                name = "all";
                desc = "nvim. Does NOT touch locks — that's intentional";
                extra = [ "(re-runs every gated activation; opt-in only)" ];
                summary = "nvim. Does NOT touch locks — that is opt-in only";
              }
            ];
          }
          {
            name = "clean";
            syntax = "clean [dir]";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            desc = "Interactive fzf TUI to scan/reclaim disk space: build";
            summary = "Interactive TUI to scan/reclaim disk space (build dirs, caches, core dumps, nix gc)";
            extra = [
              "dirs (node_modules, target, .next, dist, vendor,"
              ".venv), ~/.cache subdirs, ~/core dumps, and nix gc."
              "Scans [dir] (default $HOME). Nothing deleted without"
              "confirmation."
            ];
          }
          {
            name = "iso";
            platform = "all";
            group = "wrapper";
            complete = "custom";
            expand = true;
            desc = "Build the NixOS installer ISO or burn it to a USB device";
            sub = [
              {
                name = "build";
                syntax = "build [args]";
                desc = "Build the installer ISO with --impure";
              }
              {
                name = "path";
                syntax = "path [args]";
                desc = "Build the ISO and print the output path";
              }
              {
                name = "devices";
                desc = "List removable/block devices";
              }
              {
                name = "burn";
                syntax = "burn <device> --yes";
                desc = "Build the ISO and write it to a USB device";
              }
              {
                name = "help";
                desc = "Show nixos-iso help";
              }
            ];
          }

          {
            name = "switch";
            platform = "all";
            group = "rebuild";
            desc = "Build and activate (default boot entry on NixOS);";
            extra = [ "auto-prunes old generations to current + 1 previous" ];
            summary = "Build and activate the configuration";
          }
          {
            name = "boot";
            platform = "nixos";
            group = "rebuild";
            desc = "Build and set as next-boot only (NixOS)";
          }
          {
            name = "test";
            platform = "nixos";
            group = "rebuild";
            desc = "Activate without making it the default (NixOS)";
          }
          {
            name = "build";
            platform = "all";
            group = "rebuild";
            desc = "Build without activating";
          }
          {
            name = "dry-build";
            platform = "nixos";
            group = "rebuild";
            desc = "Show what would build, don't fetch/build";
          }
          {
            name = "dry-activate";
            platform = "nixos";
            group = "rebuild";
            desc = "Show what activate would do, don't activate (NixOS)";
          }
          {
            name = "build-vm";
            platform = "nixos";
            group = "rebuild";
            desc = "Build a VM image of the configuration (NixOS)";
          }
          {
            name = "build-vm-with-bootloader";
            platform = "nixos";
            group = "rebuild";
            desc = "Same, including bootloader (NixOS)";
          }
          {
            name = "repl";
            platform = "nixos";
            group = "rebuild";
            desc = "Open a nix repl scoped to the configuration (NixOS)";
          }
          {
            name = "rollback";
            platform = "nixos";
            group = "rebuild";
            desc = "Roll back to the previous generation";
          }
          {
            name = "generations";
            platform = "all";
            group = "rebuild";
            desc = "List system/home-manager generations";
          }
          {
            name = "gc";
            syntax = "gc [args]";
            platform = "all";
            group = "rebuild";
            complete = "custom";
            desc = "No args: nh clean (all profiles + gcroots + store gc).";
            extra = [ "With args: nix-collect-garbage <args>." ];
            summary = "No args: nh clean; with args: nix-collect-garbage <args>";
          }
          {
            name = "news";
            platform = "standalone";
            group = "rebuild";
            desc = "Read home-manager release notes (non-NixOS)";
          }
          {
            name = "instantiate";
            platform = "standalone";
            group = "rebuild";
            desc = "home-manager instantiate (non-NixOS)";
          }
          {
            name = "help";
            platform = "all";
            group = "meta";
            desc = "Show this help message";
          }

          {
            name = "edit";
            platform = "standalone";
            group = "hidden";
            desc = "Open the home configuration in $VISUAL or $EDITOR";
          }
          {
            name = "option";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Inspect configuration option";
          }
          {
            name = "init";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Initialize a configuration in the given directory";
          }
          {
            name = "remove-generations";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Remove indicated generations";
          }
          {
            name = "expire-generations";
            platform = "standalone";
            group = "hidden";
            complete = "custom";
            desc = "Remove generations older than timestamp";
          }
          {
            name = "packages";
            platform = "standalone";
            group = "hidden";
            desc = "List all packages installed in home-manager-path";
          }
          {
            name = "uninstall";
            platform = "standalone";
            group = "hidden";
            desc = "Remove Home Manager";
          }
        ];

        byName =
          name: lib.findFirst (c: c.name == name) (throw "stubbe.lib.hm: no such command ${name}") commands;
        pad = n: lib.concatStrings (lib.genList (_: " ") n);

        descCol = 24;
        helpRow =
          syntax: desc: extra:
          let
            head = "  " + syntax;
          in
          lib.concatStringsSep "\n" (
            [ (head + pad (lib.max 2 (descCol - lib.stringLength head)) + desc) ]
            ++ map (l: pad (descCol + 2) + l) extra
          );

        zshQuote = s: "'" + lib.replaceStrings [ "'" ] [ "'\\''" ] s + "'";
        zshRow = e: zshQuote "${e.name}:${e.summary or e.desc}";
      in
      {
        inherit commands;

        renderHelp =
          group:
          lib.concatMapStringsSep "\n" (c: helpRow c.syntax c.desc c.extra) (
            lib.filter (c: c.group == group) commands
          );
        renderSubHelp =
          name:
          lib.concatMapStringsSep "\n" (s: helpRow (s.syntax or s.name) s.desc (s.extra or [ ]))
            (byName name).sub;

        renderExpandedHelp =
          group:
          lib.concatMapStringsSep "\n" (
            c:
            if c.expand then
              lib.concatMapStringsSep "\n" (
                s: helpRow "${c.name} ${s.syntax or s.name}" s.desc (s.extra or [ ])
              ) c.sub
            else
              helpRow c.syntax c.desc c.extra
          ) (lib.filter (c: c.group == group) commands);

        renderZsh =
          indent: platform:
          lib.concatMapStringsSep "\n${indent}" zshRow (lib.filter (c: c.platform == platform) commands);
        renderSubZsh = indent: name: lib.concatMapStringsSep "\n${indent}" zshRow (byName name).sub;

        plainVerbs = lib.concatMapStringsSep "|" (c: c.name) (
          lib.filter (c: c.complete == null && c.sub == null) commands
        );

        nixosVerbs = lib.concatMapStringsSep ", " (c: c.name) (
          lib.filter (c: c.group == "rebuild" && c.platform != "standalone") commands
        );
        subNames = name: lib.concatMapStringsSep "|" (s: s.name) (byName name).sub;
      };
  };
}
