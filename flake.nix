{
  description = "Nix module to self-host Affine";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSupportedSystems = function: nixpkgs.lib.genAttrs [ "x86_64-linux" ]
        (system: function (import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        }));
    in
    {
      formatter = forAllSupportedSystems (pkgs: pkgs.nixpkgs-fmt);

      overlays.default = final: prev: {
        affine-server = final.callPackage ./nix/packages { };
      };

      packages = forAllSupportedSystems (pkgs: {
        affine-server = pkgs.affine-server;
        default = pkgs.affine-server;
      });
    };
}
