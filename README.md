# Hermes Agent Nix Flake

A flake that adds declarative **profiles** to
[Hermes Agent](https://github.com/NousResearch/hermes-agent) on NixOS and Home
Manager. It is built for bot mode: each bot is a Hermes profile, and each
profile declares its own ingredients:

- A soul (`SOUL.md`)
- Memories (seeded once, then owned by the agent)
- Skills
- Model and config, including MCP servers and messaging platforms
- Cron routines

Upstream still owns the package, the default profile and the units. This flake
only adds `services.hermes-agent.profiles.<name>`.

## Use

Import one module. It pulls in upstream's module as well.

```nix
{
  inputs.hermes-agent.url = "github:NousResearch/hermes-agent";
  inputs.hermes-agent-nix = {
    url = "github:<owner>/hermes-agent-nix";
    # Keep one Hermes, with the nixpkgs revision you already pin for it.
    inputs.hermes-agent.follows = "hermes-agent";
  };
}
```

Use `hermes-agent-nix.nixosModules.default` in a host or
`hermes-agent-nix.homeManagerModules.default` in a home.

```nix
services.hermes-agent = {
  enable = true;
  profiles.coder = {
    description = "Writes and reviews Nix code.";
    soul = ./examples/coder-soul.md;
    memories."USER.md" = "Prefers small, reviewable changes.";
    skills.nix = inputs.nix-skills + "/skills/nix";
    settings = {
      model.default = "anthropic/claude-sonnet-4";
      platforms.telegram.enabled = true;
    };
    # Bot token and API keys: a runtime path, never a store path.
    environmentFiles = [ config.sops.secrets."hermes/coder".path ];
    cron.jobs.brief = {
      schedule = "0 7 * * *";
      prompt = "Summarise open PRs.";
      deliver = "origin";
    };
  };
};
```

## What happens on activation

Under `<hermes home>/profiles/<name>/`, state follows seed + deep-merge. What
the agent changes at runtime survives; what Nix declares wins.

- `settings`, `mcpServers`: deep-merged into `config.yaml`. Nix keys win,
  other keys stay.
- `description`: deep-merged into `profile.yaml`. Bot Mode keys stay.
- `environment`, `environmentFiles`: `.env` is rebuilt every time.
- `soul`: `SOUL.md` is installed every time.
- `memories`: copied only if the file does not exist.
- `skills`: read-only through `skills.external_dirs`. Skills the agent
  writes stay in the profile's own `skills/`.
- `cron.jobs`: merged by job id. Declared fields win; runtime fields and
  jobs you did not declare stay.
- `hermesHomeFiles`: installed every time.

The gateway multiplexes all profiles in one process by default. It refuses
to when two profiles hold the same bot credential, so give each bot its own
token. Nix can compare `*_TOKEN` values set in `environment` only; tokens
inside `environmentFiles` are your responsibility.

## Notes

- A profile named `default` is rejected; configure the main profile through
  upstream's `services.hermes-agent.settings`.
- `_config_version` is not stamped into profile configs. Whether Hermes
  migrates a missing version on its own is not verified against the real
  package.
- This flake reads `moduleCommon.nix` and `configMergeScript.nix` from the
  locked `hermes-agent` input. They are upstream-internal paths: bump that
  input together with a run of the checks.
- On a NixOS host with impermanence, persist `services.hermes-agent.stateDir`.

## Checks

```bash
nix flake check
nix build .#checks.x86_64-linux.profiles-render   # renderer, no VM
nix build .#checks.x86_64-linux.nixos-profiles    # VM, stub Hermes package
nix build .#checks.x86_64-linux.hm-profiles       # Home Manager build + run
```

The NixOS and Home Manager checks use a stub Hermes package. The real one is a
large uncached build, so these checks do not prove that it starts.

See `AGENTS.md` for repository rules.
