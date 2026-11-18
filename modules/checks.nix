# Fast checks that need no VM and no Hermes package build.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      common = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };
      mergeScript = pkgs.callPackage "${inputs.hermes-agent}/nix/configMergeScript.nix" { };
      profileOptions = import ./_lib/profileOptions.nix { inherit lib common; };

      skill = pkgs.writeTextDir "SKILL.md" "---\nname: demo\ndescription: demo\n---\n";

      # Evaluate through the option system so defaults and types apply.
      profiles =
        (lib.evalModules {
          modules = [
            {
              options.profiles = lib.mkOption { type = lib.types.attrsOf profileOptions; };
              config.profiles = {
                coder = {
                  description = "Writes code.";
                  soul = "You are the coder.";
                  memories."USER.md" = "seeded user";
                  skills.demo = skill;
                  settings.model.default = "test/model";
                  environment.COMMON = "yes";
                  environmentFiles = [ "/tmp/hermes-check-secret.env" ];
                  mcpServers.fs = {
                    command = "mcp-fs";
                    args = [ "/srv" ];
                  };
                  cron.jobs.brief = {
                    schedule = "0 7 * * *";
                    prompt = "Morning brief";
                    deliver = "origin";
                  };
                };
                writer.settings.model.default = "test/writer";
                off = {
                  enable = false;
                  soul = "never installed";
                };
              };
            }
          ];
        }).config.profiles;

      script = import ./_lib/renderProfiles.nix {
        inherit
          lib
          pkgs
          common
          mergeScript
          profiles
          ;
        hermesHome = "/tmp/hermes-check-home";
        modes = {
          dir = "0700";
          file = "0600";
          config = "0600";
          env = "0600";
        };
      };
    in
    {
      checks.profiles-render =
        pkgs.runCommand "profiles-render"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ];
          }
          ''
            home=/tmp/hermes-check-home
            c=$home/profiles/coder
            printf 'SECRET_TOKEN=abc\n' > /tmp/hermes-check-secret.env

            apply() { ${pkgs.writeShellScript "apply-profiles" script}; }
            fail() { echo "FAIL: $*" >&2; exit 1; }

            apply

            # First activation: everything declared is rendered.
            grep -q 'You are the coder.' $c/SOUL.md || fail soul
            grep -q 'seeded user' $c/memories/USER.md || fail memory
            grep -q 'test/model' $c/config.yaml || fail config
            grep -q 'mcp-fs' $c/config.yaml || fail mcp
            grep -q 'external_dirs' $c/config.yaml || fail skills-dir
            grep -q 'description: Writes code.' $c/profile.yaml || fail description
            grep -q 'COMMON=yes' $c/.env || fail env
            grep -q 'SECRET_TOKEN=abc' $c/.env || fail env-file
            [ "$(jq -r '.jobs[0].id' $c/cron/jobs.json)" = brief ] || fail cron
            grep -q 'test/writer' $home/profiles/writer/config.yaml || fail writer
            [ ! -e $home/profiles/off ] || fail disabled-profile
            ext=$(sed -n 's/^ *- //p' $c/config.yaml | grep hermes-skills-coder)
            [ -f "$ext/demo/SKILL.md" ] || fail skill-resolves

            # Runtime state the agent owns.
            echo 'runtime_key: 1' >> $c/config.yaml
            sed -i 's#test/model#tampered#' $c/config.yaml
            echo 'ui_meta: {hermes-bots: {}}' >> $c/profile.yaml
            echo 'agent edit' > $c/memories/USER.md
            echo 'JUNK=1' >> $c/.env
            jq '.jobs[0].next_run_at = "T" | .jobs[0].prompt = "tampered" | .jobs += [{"id":"agent","schedule":"x","prompt":"y"}]' \
              $c/cron/jobs.json > /tmp/j && mv /tmp/j $c/cron/jobs.json
            mkdir -p $c/skills/mine && echo mine > $c/skills/mine/SKILL.md
            echo 'tampered soul' > $c/SOUL.md

            apply

            grep -q 'runtime_key: 1' $c/config.yaml || fail runtime-key-lost
            grep -q 'test/model' $c/config.yaml || fail nix-key-not-restored
            grep -q 'ui_meta' $c/profile.yaml || fail ui-meta-lost
            grep -q 'agent edit' $c/memories/USER.md || fail memory-overwritten
            grep -q 'JUNK' $c/.env && fail env-not-rebuilt
            [ "$(jq -r '.jobs[] | select(.id=="brief") | .next_run_at' $c/cron/jobs.json)" = T ] || fail runtime-field-lost
            [ "$(jq -r '.jobs[] | select(.id=="brief") | .prompt' $c/cron/jobs.json)" = "Morning brief" ] || fail declared-field-not-restored
            [ "$(jq '.jobs | length' $c/cron/jobs.json)" = 2 ] || fail agent-job-lost
            [ -f $c/skills/mine/SKILL.md ] || fail agent-skill-lost
            grep -q 'You are the coder.' $c/SOUL.md || fail soul-not-enforced

            touch $out
          '';
    };
}
