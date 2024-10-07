{
  description = "Tarn - layout generators for River";
  inputs = {
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
        packages.tarn = pkgs.stdenv.mkDerivation {
          pname = "tarn";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            zig_0_11.hook

            pkg-config
            wayland
            wayland-protocols
            wayland-scanner
          ];
        };
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
