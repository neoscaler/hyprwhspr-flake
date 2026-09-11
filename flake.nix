{
  description = "Declarative hyprwhspr speech-to-text: Nix package + Home Manager/NixOS modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Upstream pinned to a release tag instead of the moving main branch.
    hyprwhspr-src = {
      url = "github:goodroot/hyprwhspr/v1.43.0";
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

      # Modul-Eval für den Check: die vom NixOS-Modul gesetzten Optionen
      # (udev, tmpfiles, user, package) forcieren. Fängt Optionstyp-/Eval-Fehler,
      # ohne ein komplettes System inkl. dessen Boot-/User-Assertions zu bauen.
      nixosModuleEval =
        let
          cfg = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.hyprwhspr
              {
                services.hyprwhspr.system.package = hyprwhspr;
                services.hyprwhspr.system.users = [ "nixos-module-eval" ];
              }
            ];
          }).config;
        in
        pkgs.writeText "hyprwhspr-nixos-module-eval.json" (builtins.toJSON {
          package = cfg.services.hyprwhspr.system.package.outPath;
          udevRules = cfg.services.udev.extraRules;
          tmpfiles = cfg.systemd.tmpfiles.rules;
          extraGroups = cfg.users.users.nixos-module-eval.extraGroups;
        });
    in
    {
      packages.${system} = {
        inherit hyprwhspr;
        default = hyprwhspr;
      };

      formatter.${system} = pkgs.nixfmt;

      checks.${system} = {
        hyprwhspr = hyprwhspr;
        nixos-module = nixosModuleEval;
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
