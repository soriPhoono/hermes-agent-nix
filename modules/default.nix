{ inputs, ... }: {
  imports = [
    (inputs.flake-file.lib.flakeModules.flake-parts-builder ../flake-system)
    inputs.flake-file.flakeModules.default

    ./inputs.nix
    ./checks.nix
    ./checks-nixos.nix
    ./checks-hm.nix

    # Add your nix expression here for import
  ];

  flake-file.outputs = "flake-parts";

  flake = {
    nixosModules = rec {
      default = hermes;
      hermes = import ./nixosModule.nix inputs;
    };
    homeManagerModules = rec {
      default = hermes;
      hermes = import ./homeManagerModule.nix inputs;
    };
  };
}
