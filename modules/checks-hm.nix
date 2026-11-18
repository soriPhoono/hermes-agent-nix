# Home Manager check: evaluate and build a real homeManagerConfiguration with
# our module, then run the profile activation snippet it generated.
{ inputs, self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.hm-profiles = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
        let
          hm = inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home = {
                  username = "hm-check";
                  homeDirectory = "/tmp/hm-check";
                  stateVersion = "24.11";
                };
                services.hermes-agent = {
                  enable = true;
                  package = import ./_lib/stubPackage.nix { inherit pkgs; };
                  hermesHome = "/tmp/hm-check-hermes";
                  profiles = {
                    coder = {
                      soul = "You are the coder.";
                      settings.model.default = "test/coder";
                      cron.jobs.brief = {
                        schedule = "0 7 * * *";
                        prompt = "Morning brief";
                      };
                    };
                    writer.settings.model.default = "test/writer";
                  };
                };
              }
            ];
          };
          snippet = pkgs.writeShellScript "hm-profiles" hm.config.home.activation.hermesAgentProfiles.data;
        in
        pkgs.runCommand "hm-profiles" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
          fail() { echo "FAIL: $*" >&2; exit 1; }
          home=/tmp/hm-check-hermes

          # The full generation builds and carries our activation entry.
          grep -q hermesAgentProfiles ${hm.activationPackage}/activate || fail not-in-activate

          # The profile snippet runs (no DRY_RUN_CMD) and renders both bots.
          ${snippet}
          grep -q 'You are the coder.' $home/profiles/coder/SOUL.md || fail soul
          grep -q 'test/writer' $home/profiles/writer/config.yaml || fail writer
          [ "$(stat -c %a $home/profiles/coder/config.yaml)" = 600 ] || fail mode
          [ "$(stat -c %a $home/profiles/coder)" = 700 ] || fail dir-mode

          # Dry run changes nothing.
          rm -rf $home
          DRY_RUN_CMD=echo ${snippet} > /dev/null
          [ ! -e $home/profiles/coder/SOUL.md ] || fail dry-run-wrote

          touch $out
        ''
      );
    };
}
