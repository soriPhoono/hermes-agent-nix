{
  flake-file.inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-file.url = "github:denful/flake-file";

    # Upstream Hermes: this flake layers declarative profiles on its modules.
    # nixpkgs is deliberately not overridden here; consumers decide.
    hermes-agent.url = "github:NousResearch/hermes-agent";

    # Only used by the Home Manager eval check.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
