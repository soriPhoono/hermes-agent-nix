# NixOS: declarative profiles on top of upstream's services.hermes-agent.
#
# Imported as `import ./nixosModule.nix inputs`. It pulls in upstream's module,
# so consumers import this one module only.
inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hermes-agent;

  common = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };
  profileOptions = import ./_lib/profileOptions.nix { inherit lib common; };
  mergeScript = pkgs.callPackage "${inputs.hermes-agent}/nix/configMergeScript.nix" { };

  hermesHome = "${cfg.stateDir}/.hermes";

  script = import ./_lib/renderProfiles.nix {
    inherit
      lib
      pkgs
      common
      mergeScript
      hermesHome
      ;
    inherit (cfg) profiles;
    owner = "${cfg.user}:${cfg.group}";
    # Same group-writable layout as upstream's own state directories.
    modes = {
      dir = "2770";
      file = "0640";
      config = "0640";
      env = "0640";
    };
  };

  enabled = lib.filterAttrs (_: p: p.enable) cfg.profiles;

  # A bot token can belong to one profile only. Only values written in Nix can
  # be compared here; tokens inside environmentFiles cannot.
  tokenOwners = lib.foldlAttrs (
    acc: profile: p:
    lib.foldlAttrs (
      acc': var: value:
      if lib.hasSuffix "_TOKEN" var then
        acc' // { ${value} = (acc'.${value} or [ ]) ++ [ "${profile}:${var}" ]; }
      else
        acc'
    ) acc p.environment
  ) { } enabled;
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  options.services.hermes-agent.profiles = lib.mkOption {
    type = lib.types.attrsOf profileOptions;
    default = { };
    description = ''
      Hermes profiles (bots), each a directory under
      `<stateDir>/.hermes/profiles/<name>`. Config is deep-merged, memories
      are seeded once and cron jobs are merged by id, so what the agent
      changes at runtime survives an activation.
    '';
  };

  config = lib.mkIf (cfg.enable && enabled != { }) {
    assertions = [
      {
        assertion = lib.all (n: builtins.match "[a-z0-9][a-z0-9_-]*" n != null) (
          lib.attrNames cfg.profiles
        );
        message = "services.hermes-agent.profiles: names must match [a-z0-9][a-z0-9_-]*.";
      }
      {
        assertion = !(cfg.profiles ? default);
        message = "services.hermes-agent.profiles: \"default\" is the main profile; use services.hermes-agent.settings for it.";
      }
      {
        assertion = lib.all (owners: lib.length owners == 1) (lib.attrValues tokenOwners);
        message = "services.hermes-agent.profiles: one bot token is set in more than one profile: ${
          lib.concatStringsSep ", " (
            lib.concatLists (lib.filter (o: lib.length o > 1) (lib.attrValues tokenOwners))
          )
        }";
      }
    ];

    system.activationScripts."hermes-agent-profiles" = lib.stringAfter [ "hermes-agent-setup" ] script;

    # Changed profiles take effect on the next gateway start.
    systemd.services.hermes-agent.restartTriggers = [
      (pkgs.writeText "hermes-profiles-script" script)
    ];
  };
}
