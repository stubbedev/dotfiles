# Branch of the pkgs.stubbe helper tree (see ./default.nix).
# Shell fragments for config.stubbe.setup.<name>.script. These emit text; the
# other branches build derivations.
_: {
  stubbe.pkgsLib.setup =
    {
      final,
      lib,
      stubbe,
      ...
    }:
    {
      jsonWrite =
        {
          name,
          target,
          value,
          mode ? "0600",
        }:
        let
          valueFile = stubbe.gen.json "${name}.json" value;
        in
        ''
          if ! cmp -s ${valueFile} ${lib.escapeShellArg target}; then
            install -D -m ${mode} ${valueFile} ${lib.escapeShellArg "${target}.hm-tmp"}
            mv ${lib.escapeShellArg "${target}.hm-tmp"} ${lib.escapeShellArg target}
          fi
        '';

      # jq against the LIVE file, so anything the owning app wrote between
      # evaluation and activation survives; only `key` is replaced.
      jsonSet =
        {
          name,
          target,
          key,
          value,
          mode ? "0600",
        }:
        let
          valueFile = stubbe.gen.json "${name}.json" value;
          tmp = lib.escapeShellArg "${target}.hm-tmp";
          dst = lib.escapeShellArg target;
          jq = lib.getExe final.jq;
        in
        ''
          install -D -m ${mode} /dev/null ${tmp}
          if [ -f ${dst} ]; then
            ${jq} --slurpfile v ${valueFile} '.[${builtins.toJSON key}] = $v[0]' ${dst} > ${tmp}
          else
            ${jq} -n --slurpfile v ${valueFile} '{ ${builtins.toJSON key}: $v[0] }' > ${tmp}
          fi
          if cmp -s ${tmp} ${dst}; then
            rm -f ${tmp}
          else
            mv ${tmp} ${dst}
          fi
        '';
    };
}
