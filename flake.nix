{
  description = "NixOS hardware support for the MNT Pocket Reform with i.MX8MP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      systems = [ "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      nixosModules = {
        pocket-reform-imx8mp = import ./modules/default.nix;
        pocket-reform = self.nixosModules.pocket-reform-imx8mp;
        default = self.nixosModules.pocket-reform-imx8mp;
      };

      packages = forAllSystems (pkgs: rec {
        qcacld2 = pkgs.callPackage ./packages/qcacld2.nix {
          kernel = pkgs.linuxPackages_latest.kernel;
        };
        qcacld2-firmware = pkgs.callPackage ./packages/qcacld2-firmware.nix { };
        panel-mnt-pocket-reform = pkgs.callPackage ./packages/panel-mnt-pocket-reform.nix {
          kernel = pkgs.linuxPackages_latest.kernel;
        };
        mnt-pocket-dtb = pkgs.callPackage ./packages/mnt-pocket-dtb.nix { };
        mnt-sc = pkgs.callPackage ./packages/mnt-sc.nix {
          kernel = pkgs.linuxPackages_latest.kernel;
          inherit qcacld2;
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      checks = forAllSystems (pkgs: {
        inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) mnt-pocket-dtb qcacld2-firmware;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            dtc
            nixfmt
            ubootTools
          ];
        };
      });
    };
}
