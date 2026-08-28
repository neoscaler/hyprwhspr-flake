{
  description = "Declarative hyprwhspr speech-to-text: Nix package + Home Manager/NixOS modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Upstream pinned to a release tag instead of the moving main branch.
    hyprwhspr-src = {
      url = "github:goodroot/hyprwhspr/v1.42.3";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      hyprwhspr-src,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      hyprwhspr = pkgs.callPackage ./pkgs/hyprwhspr {
        inherit hyprwhspr-src;
      };
    in
    {
      packages.${system} = {
        inherit hyprwhspr;
        default = hyprwhspr;
      };

      overlays.default = final: prev: {
        hyprwhspr = final.callPackage ./pkgs/hyprwhspr {
          inherit (inputs) hyprwhspr-src;
        };
      };

      homeManagerModules.hyprwhspr = import ./modules/home-manager.nix;
      homeManagerModules.default = self.homeManagerModules.hyprwhspr;

      nixosModules.hyprwhspr = import ./modules/system.nix;
      nixosModules.default = self.nixosModules.hyprwhspr;
    };
}
