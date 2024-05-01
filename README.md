# Tarn

Tarn is a collection of River layout generators (currently N=1).

## Included layouts

- tarn-dwindle: a dwindling layout with horizontal and vertical dwindle ratios
  specifiably separately

## Usage

Tarn provides separate binaries for each layout.

```bash
$ tarn-dwindle -h
```

### tarn-dwindle

You can send layout commands to update the Dwindle layout ratios, for example:

```bash
riverctl map normal Super+Control H send-layout-cmd tarn-dwindle "horizontal-ratio -0.05"
riverctl map normal Super+Control J send-layout-cmd tarn-dwindle "vertical-ratio +0.05"
riverctl map normal Super+Control K send-layout-cmd tarn-dwindle "vertical-ratio -0.05"
riverctl map normal Super+Control L send-layout-cmd tarn-dwindle "horizontal-ratio +0.05"
```

## Installing

Using Nix

```bash
$ nix build git+https://codeberg.org/tomcur/tarn.git
```

You can use the provided flake to install Tarn in a flake-based NixOS configuration. For example:

```nix
{
  description = "Your system config";
  inputs = {
    # ..
    tarn = {
      url = "git+https://codeberg.org/tomcur/tarn.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { nixpkgs, tarn, ... }: {
    nixosConfigurations = {
      yourSystem =
        let
          system = "x86_64-linux";
          modules = [
            {
              nixpkgs.overlays = [
                (self: super: {
                  tarn = tarn.packages.${system}.default;
                })
              ]
            }
          ];
        in
        nixpkgs.lib.nixosSystem {
          inherit system modules;
        };
    };
  };
}
```
