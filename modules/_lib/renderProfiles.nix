# Renders the activation script for declared Hermes profiles.
#
#   run     command prefix: "" on NixOS, "$DRY_RUN_CMD " on Home Manager
#   owner   "user:group" for everything we write, or null (the caller's user)
#   modes   { dir, file, config, env } octal modes
#
# Semantics under <hermesHome>/profiles/<name>/ (seed + deep-merge):
#   config.yaml        deep-merged; Nix keys win, runtime keys stay
#   profile.yaml       description deep-merged; Bot Mode keys stay
#   .env               rebuilt each time (only if env or env files are set)
#   SOUL.md            installed each time
#   memories/*         seeded only if absent
#   cron/jobs.json     merged by job id; declared fields win, runtime stay
#   hermesHomeFiles    installed each time
#   skills             not copied; exposed through skills.external_dirs
{
  lib,
  pkgs,
  common,
  mergeScript,
  hermesHome,
  profiles,
  modes,
  run ? "",
  owner ? null,
}:
let
  enabled = lib.filterAttrs (_: p: p.enable) profiles;

  ownerFlags = lib.optionalString (owner != null) (
    let
      parts = lib.splitString ":" owner;
    in
    "-o ${lib.head parts} -g ${lib.last parts}"
  );
  inst = "${run}install ${ownerFlags}";

  # A path or store path is used as is; literal text becomes a store file.
  asFile =
    name: v:
    if builtins.isPath v || lib.isStorePath v then
      v
    else
      pkgs.writeText (lib.strings.sanitizeDerivationName name) v;

  instFile = mode: src: dest: ''
    ${inst} -d -m ${modes.dir} ${lib.escapeShellArg (builtins.dirOf dest)}
    ${inst} -m ${mode} ${src} ${lib.escapeShellArg dest}
  '';

  # jobs.json: update declared jobs by id, keep every other field and job.
  cronMerge = pkgs.writeShellScript "hermes-cron-merge" ''
    set -eu
    decl="$1"; dest="$2"
    cur="$(mktemp)"
    if [ -s "$dest" ]; then cat "$dest" > "$cur"; else echo '{}' > "$cur"; fi
    ${pkgs.jq}/bin/jq --slurpfile d "$decl" '
      ($d[0]) as $decl
      | (.jobs // []) as $jobs
      | . + { jobs:
          ( ($jobs | map(. as $j
              | ($decl | map(select(.id == $j.id)) | first) as $o
              | if $o == null then $j else $j * $o end))
          + ($decl | map(select(.id as $i | ($jobs | map(.id) | index($i)) == null))) ) }
    ' "$cur" > "$cur.out"
    cat "$cur.out" > "$dest"
    rm -f "$cur" "$cur.out"
  '';

  renderProfile =
    name: p:
    let
      dir = "${hermesHome}/profiles/${name}";
      skillsFarm = pkgs.linkFarm "hermes-skills-${name}" (
        lib.mapAttrsToList (name: path: { inherit name path; }) p.skills
      );
      settings = lib.recursiveUpdate p.settings (
        lib.optionalAttrs (p.mcpServers != { }) { mcp_servers = common.mcpServersToConfig p.mcpServers; }
        // lib.optionalAttrs (p.skills != { }) {
          skills.external_dirs = (p.settings.skills.external_dirs or [ ]) ++ [ "${skillsFarm}" ];
        }
      );
      settingsJson = pkgs.writeText "hermes-${name}-settings.json" (builtins.toJSON settings);
      envScript = common.mkEnvScript {
        inherit pkgs;
        inherit (p) environment;
      };
      jobs = lib.mapAttrsToList (
        id: job:
        {
          inherit id;
          name = id;
        }
        // job
      ) p.cron.jobs;
      jobsJson = pkgs.writeText "hermes-${name}-jobs.json" (builtins.toJSON jobs);
      chownFile = f: lib.optionalString (owner != null) "${run}chown ${owner} ${lib.escapeShellArg f}";
    in
    ''
      # ── profile ${name} ──
      ${inst} -d -m ${modes.dir} ${
        lib.escapeShellArgs [
          dir
          "${dir}/memories"
          "${dir}/cron"
        ]
      }

      ${lib.optionalString (settings != { }) ''
        ${run}${mergeScript} ${settingsJson} ${dir}/config.yaml
        ${run}chmod ${modes.config} ${dir}/config.yaml
        ${chownFile "${dir}/config.yaml"}
      ''}
      ${lib.optionalString (p.description != null) ''
        ${run}${mergeScript} ${
          pkgs.writeText "hermes-${name}-profile.json" (builtins.toJSON { inherit (p) description; })
        } ${dir}/profile.yaml
        ${run}chmod ${modes.file} ${dir}/profile.yaml
        ${chownFile "${dir}/profile.yaml"}
      ''}
      ${lib.optionalString (p.environment != { } || p.environmentFiles != [ ]) ''
        ${run}${envScript} ${dir}/.env ${modes.env} ${lib.escapeShellArgs p.environmentFiles}
        ${chownFile "${dir}/.env"}
      ''}
      ${lib.optionalString (p.soul != null) (
        instFile modes.file (asFile "${name}-SOUL.md" p.soul) "${dir}/SOUL.md"
      )}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (f: v: ''
          if [ ! -e ${lib.escapeShellArg "${dir}/memories/${f}"} ]; then
            ${instFile modes.file (asFile "${name}-${f}" v) "${dir}/memories/${f}"}
          fi
        '') p.memories
      )}
      ${lib.optionalString (p.cron.jobs != { }) ''
        ${run}${cronMerge} ${jobsJson} ${dir}/cron/jobs.json
        ${run}chmod ${modes.file} ${dir}/cron/jobs.json
        ${chownFile "${dir}/cron/jobs.json"}
      ''}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          f: v: instFile modes.file (asFile "${name}-${f}" v) "${dir}/${f}"
        ) p.hermesHomeFiles
      )}
    '';
in
lib.concatStringsSep "\n" (lib.mapAttrsToList renderProfile enabled)
