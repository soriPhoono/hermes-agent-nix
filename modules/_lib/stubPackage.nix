# A stand-in for the Hermes package in tests. The real one is a large
# uv2nix/pnpm build; the modules only read bin/hermes and hermesVenv (for
# DEFAULT_CONFIG's _config_version).
{ pkgs }:
let
  fakeCli = pkgs.runCommand "fake-hermes-cli" { } ''
    mkdir -p $out/hermes_cli
    touch $out/hermes_cli/__init__.py
    echo 'DEFAULT_CONFIG = {"_config_version": 1}' > $out/hermes_cli/config_defaults.py
  '';
  venv = pkgs.writeShellScriptBin "python3" ''
    export PYTHONPATH=${fakeCli}
    exec ${pkgs.python3}/bin/python3 "$@"
  '';
in
(pkgs.writeShellScriptBin "hermes" "exec sleep infinity").overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    hermesVenv = venv;
  };
})
