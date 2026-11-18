# Hermes Agent Nix Flake

A flake that adds declarative **profiles** to
[Hermes Agent](https://github.com/NousResearch/hermes-agent) on NixOS and Home
Manager. It is built for bot mode: each bot is a Hermes profile, and each
profile declares its own ingredients:

- A soul (`SOUL.md`)
- Memories (seeded once, then owned by the agent)
- Skills
- Model and config, including MCP servers
- Messaging platforms (tokens through secret env files)
- Cron routines

Upstream still owns the package, the default profile and the units. This flake
only adds `services.hermes-agent.profiles.<name>`.

Status: planning. See `AGENTS.md` for repository rules.
