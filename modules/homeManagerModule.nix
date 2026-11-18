# Home Manager: declarative profiles on top of upstream's services.hermes-agent.
#
# Imported as `import ./homeManagerModule.nix inputs`. It pulls in upstream's
# module, so consumers import this one module only.
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
  shared = import ./_lib/assertions.nix {
    inherit lib;
    inherit (cfg) profiles;
  };

  script = import ./_lib/renderProfiles.nix {
    inherit
      lib
      pkgs
      common
      mergeScript
      ;
    inherit (cfg) hermesHome profiles;
    # Home Manager's dry-run prefix; empty on a real activation.
    run = "$DRY_RUN_CMD ";
    # One user owns this state, so no group access.
    modes = {
      dir = "0700";
      file = "0600";
      config = "0600";
      env = "0600";
    };
  };
in
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  options.services.hermes-agent.profiles = lib.mkOption {
    type = lib.types.attrsOf profileOptions;
    default = { };
    description = ''
      Hermes profiles (bots), each a directory under
      `<hermesHome>/profiles/<name>`. Config is deep-merged, memories are
      seeded once and cron jobs are merged by id, so what the agent changes
      at runtime survives an activation. Profiles show up in Hermes Desktop's
      Bot Mode roster.
    '';
  };

  config = lib.mkIf (cfg.enable && shared.enabled != { }) {
    inherit (shared) assertions;

    home.activation.hermesAgentProfiles = lib.hm.dag.entryAfter [ "hermesAgentSetup" ] script;

    # Changed profiles take effect on the next gateway start.
    systemd.user.services.hermes-agent.Unit.X-Restart-Triggers = lib.mkIf cfg.gateway.enable [
      "${pkgs.writeText "hermes-profiles-script" script}"
    ];
  };
}
