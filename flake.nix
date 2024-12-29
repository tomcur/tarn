{
  description = "Tarn - layout generators for River";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };
  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      rec {
        packages.tarn = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "tarn";
          version = "0.1.0";

          src = ./.;

          deps = pkgs.callPackage ./deps.nix { };
          nativeBuildInputs = with pkgs; [
            pkg-config

            wayland
            wayland-protocols
            wayland-scanner

            zig_0_13.hook
          ];
          dontConfigure = true;
          zigBuildFlags = [
            "--system"
            "${finalAttrs.deps}"
          ];
        });
        packages.default = packages.tarn;
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig

            pkg-config
            wayland
            wayland-protocols
            wayland-scanner
          ];
          shellHook = ''
          '';
        };
      });
}
