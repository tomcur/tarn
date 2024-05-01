# Tarn

Tarn is a collection of River layout generators (currently N=1).

## Included layouts

- tarn-dwindle: a dwindling layout with horizontal and vertical dwindle ratios
  specifiably separately

## Building

Using Nix

```bash
$ nix build git+https://codeberg.org/tomcur/tarn.git
```

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
