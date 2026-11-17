{ referenceHome, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      hm = lib.findFirst (
        package: package.name or "" == "hm"
      ) (throw "checks.hm: the reference home installs no hm package") referenceHome.home.packages;
    in
    {
      checks.hm = pkgs.stubbe.check {
        name = "hm";
        timeout = 120;
        nativeBuildInputs = [
          hm
          pkgs.age
          pkgs.openssh
          pkgs.sops
          pkgs.ssh-to-age
          pkgs.yq-go
        ];
        env.sopsYaml = ../../.sops.yaml;
        text = ''
          set -euo pipefail

          fail() { echo "checks.hm: $*" >&2; exit 1; }

          dir=$(mktemp -d)
          flake="$dir/flake"
          export HOME="$dir/home" HM_FLAKE_DIR="$dir/flake-link"
          mkdir -p "$HOME/.ssh" "$flake/secrets" "$dir/elsewhere"
          ln -s "$flake" "$HM_FLAKE_DIR"
          cp "$sopsYaml" "$flake/.sops.yaml"
          chmod u+w "$flake/.sops.yaml"
          cd "$dir/elsewhere"

          recipients() { yq '[.creation_rules[].key_groups[].age[]] | join(" ")' "$flake/.sops.yaml"; }
          comment_of() { PUBKEY="$1" yq '.creation_rules[].key_groups[].age[] | select(. == strenv(PUBKEY)) | line_comment' "$flake/.sops.yaml"; }

          [[ "$(hm help)" == 'Usage: hm <command> [args]'* ]] || fail "hm help does not start with the usage line"

          age-keygen -o "$dir/first.key" 2>/dev/null
          age-keygen -o "$dir/second.key" 2>/dev/null
          first=$(age-keygen -y "$dir/first.key")
          second=$(age-keygen -y "$dir/second.key")
          before=$(recipients)

          trust_output=$(hm trust first "$first")
          [ "$(recipients)" = "$before $first" ] || fail "trust did not append $first to the recipients: $(recipients)"
          [ "$(comment_of "$first")" = first ] || fail "trust did not label $first as 'first'"
          [[ "$trust_output" == *"git -C \"$flake\" diff"* ]] || fail "hm did not resolve HM_FLAKE_DIR to $flake: $trust_output"
          [[ "$trust_output" == *$'\n\nTrusted first across 0 secret file(s).\nReview:'* ]] || fail "hm trust summary is misformatted: $trust_output"

          snapshot=$(cat "$flake/.sops.yaml")
          [[ "$(hm trust first "$first")" == *'already present'* ]] || fail "re-trusting $first was not reported as a no-op"
          [ "$(cat "$flake/.sops.yaml")" = "$snapshot" ] || fail "re-trusting $first changed .sops.yaml"

          printf 'hunter2\n\n' | hm secret set token
          export SOPS_AGE_KEY_FILE="$dir/first.key"
          hm trust second "$second"
          [ "$(recipients)" = "$before $first $second" ] || fail "trust did not append $second to the recipients: $(recipients)"
          SOPS_AGE_KEY_FILE="$dir/second.key" sops --decrypt --input-type binary --output-type binary \
            "$flake/secrets/token" > "$dir/plain"
          printf 'hunter2' | cmp -s - "$dir/plain" || fail "secrets/token is not exactly 'hunter2' readable by $second"

          status=0
          printf 'a\0b' | hm secret set nul 2>/dev/null || status=$?
          [ "$status" -eq 1 ] || fail "hm secret set accepted a value with a NUL byte (exit $status)"
          [ ! -e "$flake/secrets/nul" ] || fail "hm secret set wrote a value with a NUL byte"

          for name in ../escape /etc/escape .hidden "sub/dir" ""; do
            status=0
            printf 'x' | hm secret set "$name" 2>/dev/null || status=$?
            [ "$status" -eq 2 ] || fail "hm secret set '$name' exited $status, want 2"
          done
          [ ! -e "$flake/escape" ] || fail "hm secret set ../escape wrote outside secrets/"

          ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
          own=$(ssh-to-age < "$HOME/.ssh/id_ed25519.pub")
          [ "$(hm whoami)" = "''${HOSTNAME%%.*} $own" ] || fail "hm whoami printed '$(hm whoami)'"
          hm whoami | hm trust >/dev/null
          [ "$(comment_of "$own")" = "''${HOSTNAME%%.*}" ] || fail "piping hm whoami into hm trust did not label $own by hostname"


          touch "$out"
        '';
      };
    };
}
