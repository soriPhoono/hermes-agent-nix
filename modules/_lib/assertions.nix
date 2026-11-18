# Assertions shared by the NixOS and Home Manager modules.
{ lib, profiles }:
let
  enabled = lib.filterAttrs (_: p: p.enable) profiles;

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
  inherit enabled;

  assertions = [
    {
      assertion = lib.all (n: builtins.match "[a-z0-9][a-z0-9_-]*" n != null) (lib.attrNames profiles);
      message = "services.hermes-agent.profiles: names must match [a-z0-9][a-z0-9_-]*.";
    }
    {
      assertion = !(profiles ? default);
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
}
