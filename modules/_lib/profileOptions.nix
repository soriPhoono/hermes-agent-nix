# The shared type of `services.hermes-agent.profiles.<name>`.
#
# `common` is upstream's nix/moduleCommon.nix, called with `lib`. Its
# `deepConfigType` and `mcpServerType` are reused so a profile accepts exactly
# what upstream's own `settings` and `mcpServers` accept.
{ lib, common }:
let
  inherit (lib) mkOption mkEnableOption types;

  # A file body: a path (copied to the store) or literal text.
  fileType = types.either types.path types.lines;
in
types.submodule {
  options = {
    enable = mkEnableOption "this profile" // {
      default = true;
    };

    description = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        One or two sentences on what this bot is good at. Merged into the
        profile's `profile.yaml`, where the kanban orchestrator reads it.
      '';
    };

    soul = mkOption {
      type = types.nullOr fileType;
      default = null;
      description = "The profile's SOUL.md. Installed on every activation.";
    };

    memories = mkOption {
      type = types.attrsOf fileType;
      default = { };
      example = lib.literalExpression ''{ "USER.md" = ./USER.md; }'';
      description = ''
        Files under the profile's `memories/`. Each one is seeded only if it
        does not exist yet; afterwards the agent owns it.
      '';
    };

    skills = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = lib.literalExpression ''{ nix = inputs.nix-skills + "/skills/nix"; }'';
      description = ''
        Skills by name; each value is a directory that contains a SKILL.md.
        They are exposed read-only through `skills.external_dirs`, so skills
        the agent writes itself stay in the profile's own `skills/`.
      '';
    };

    settings = mkOption {
      type = common.deepConfigType;
      default = { };
      description = ''
        The profile's config.yaml, deep-merged into the file on disk on every
        activation. Nix keys win; keys the agent wrote at runtime stay.
        Messaging platform config goes here.
      '';
    };

    mcpServers = mkOption {
      type = types.attrsOf common.mcpServerType;
      default = { };
      description = "MCP servers, merged into `settings.mcp_servers`.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Non-secret variables for the profile's .env. Do not put secrets here:
        the Nix store is world-readable.
      '';
    };

    environmentFiles = mkOption {
      # `str`, not `path`: a path literal would copy the secret into the store.
      type = types.listOf types.str;
      default = [ ];
      example = lib.literalExpression ''[ config.sops.secrets."hermes/coder".path ]'';
      description = ''
        Runtime paths of env files (bot tokens, API keys). The profile's .env
        is rebuilt from `environment` plus these files on every activation.
        A bot token must appear in one profile only.
      '';
    };

    cron.jobs = mkOption {
      type = types.attrsOf (
        types.submodule {
          freeformType = types.attrsOf types.anything;
          options = {
            schedule = mkOption {
              type = types.str;
              example = "0 7 * * *";
              description = "The same string `hermes cron create` takes.";
            };
            prompt = mkOption {
              type = types.str;
              description = "What the agent is asked to do.";
            };
          };
        }
      );
      default = { };
      description = ''
        Cron routines, keyed by a stable job id. Declared fields win and
        runtime fields (next run, failure streak) are kept. Jobs that are not
        declared are left alone. Any other jobs.json field (`deliver`,
        `timezone`, `workdir`, ...) can be set freely.
      '';
    };

    hermesHomeFiles = mkOption {
      type = types.attrsOf fileType;
      default = { };
      description = "Extra files, relative to the profile directory. Overwritten on every activation.";
    };
  };
}
