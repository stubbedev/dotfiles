{ config, pkgs, ... }:

''
  ${pkgs.gh}/bin/gh extension install github/gh-copilot > /dev/null 2>&1
  ${pkgs.gh}/bin/gh extension upgrade github/gh-copilot > /dev/null 2>&1
  ${pkgs.bun}/bin/bun install opencode-ai@latest --global > /dev/null 2>&1
''

