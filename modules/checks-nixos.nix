# VM test: our profile layer on top of the real upstream NixOS module.
# The Hermes package is a stub (the real one is a large uv2nix/pnpm build);
# it only has to satisfy what the module reads: bin/hermes and
# hermesVenv, which supplies DEFAULT_CONFIG's _config_version.
{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.nixos-profiles = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
        let
          stub = import ./_lib/stubPackage.nix { inherit pkgs; };
          skill = pkgs.writeTextDir "SKILL.md" "---\nname: demo\ndescription: demo\n---\n";
        in
        pkgs.testers.runNixOSTest {
          name = "hermes-profiles";
          nodes.machine = {
            imports = [ self.nixosModules.default ];
            environment.etc."hermes-coder.env".text = "CODER_BOT_TOKEN=abc\n";
            services.hermes-agent = {
              enable = true;
              package = stub;
              profiles = {
                coder = {
                  description = "Writes code.";
                  soul = "You are the coder.";
                  memories."USER.md" = "seeded";
                  skills.demo = skill;
                  settings.model.default = "test/coder";
                  environmentFiles = [ "/etc/hermes-coder.env" ];
                  cron.jobs.brief = {
                    schedule = "0 7 * * *";
                    prompt = "Morning brief";
                  };
                };
                writer.settings.model.default = "test/writer";
              };
            };
          };

          testScript = ''
            home = "/var/lib/hermes/.hermes/profiles"
            machine.wait_for_unit("hermes-agent.service")

            # Rendered, and owned by the service user.
            machine.succeed(f"grep -q 'You are the coder.' {home}/coder/SOUL.md")
            machine.succeed(f"grep -q 'test/coder' {home}/coder/config.yaml")
            machine.succeed(f"grep -q 'test/writer' {home}/writer/config.yaml")
            machine.succeed(f"grep -q 'CODER_BOT_TOKEN=abc' {home}/coder/.env")
            machine.succeed(f"grep -q brief {home}/coder/cron/jobs.json")
            for f in ["SOUL.md", "config.yaml", ".env", "cron/jobs.json", "memories/USER.md"]:
                assert machine.succeed(f"stat -c %U:%G {home}/coder/{f}").strip() == "hermes:hermes", f
            # The service user can read what it needs, others cannot read the env file.
            machine.succeed(f"sudo -u hermes cat {home}/coder/.env")
            machine.fail(f"sudo -u nobody cat {home}/coder/.env")

            # Runtime edits survive a second activation.
            machine.succeed(f"echo 'runtime_key: 1' >> {home}/coder/config.yaml")
            machine.succeed(f"echo 'agent edit' > {home}/coder/memories/USER.md")
            machine.succeed(f"mkdir -p {home}/coder/skills/mine && touch {home}/coder/skills/mine/SKILL.md")
            machine.succeed(f"echo tampered > {home}/coder/SOUL.md")
            machine.succeed("/run/current-system/activate")
            machine.succeed(f"grep -q 'runtime_key: 1' {home}/coder/config.yaml")
            machine.succeed(f"grep -q 'agent edit' {home}/coder/memories/USER.md")
            machine.succeed(f"test -f {home}/coder/skills/mine/SKILL.md")
            machine.succeed(f"grep -q 'You are the coder.' {home}/coder/SOUL.md")
          '';
        }
      );
    };
}
