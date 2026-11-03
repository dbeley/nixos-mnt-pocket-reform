# nixos-mnt-pocket-reform

NixOS hardware support for the **MNT Pocket Reform with the i.MX8MP module**.

This flake provides a NixOS module that adds:

- the nixpkgs Linux 7.3.x kernel (already built in the aarch64 binary cache),
  with a small wrapper that injects the MNT device tree into the kernel's
  `dtbs` output without rebuilding the kernel;
- the MNT Pocket Reform JDI `LT070ME05000` panel driver, ported to the Linux
  7.3 DRM panel API;
- the `mnt_sc` system-controller driver (battery, backlight, GPIOs,
  power-off) speaking the RP2040's s-expression protocol;
- the `qcacld2` out-of-tree Wi-Fi driver and firmware for the QCA9377 SDIO
  module, patched for Linux 7.3;
- kernel parameters and initrd modules for the internal display, NVMe, SD and
  USB keyboard;
- a generic-extlinux-compatible boot configuration.

## Scope and compatibility

This flake targets the **i.MX8MP processor module on the V1 Pocket Reform
mainboard**. The panel driver, system controller driver and Wi-Fi driver are
SoC-independent, but the device tree, kernel wrapper and U-Boot script are
specific to i.MX8MP.

- **Mainboard 2.0**: boots, but the newer SC-controlled backlight, SC GPIO
  reset and USB mux handling need the current `mnt-linux` device tree and
  drivers. Treat V2 mainboard support as experimental.
- **Charger Module V2 and Keyboard PCB 2.0**: no kernel-visible interface
  change; they should work as-is (keep the keyboard firmware updated).
- **Other SoCs** (A311D, RK3588, QCS6490/8550): not supported by this module.
  They need a different device tree, kernel configuration and bootloader
  setup; see [`mnt-reform-platforms`](https://sr.ht/~stephano/mnt-reform-platforms).

## Usage

```nix
{
  inputs.nixos-mnt-pocket-reform.url = "github:dbeley/nixos-mnt-pocket-reform";

  outputs = { self, nixpkgs, nixos-mnt-pocket-reform, ... }: {
    nixosConfigurations.pocket-reform = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-mnt-pocket-reform.nixosModules.pocket-reform-imx8mp
        {
          hardware.mnt-pocket-reform.enable = true;
        }
        ./configuration.nix
      ];
    };
  };
}
```

`nixosModules.pocket-reform` and `nixosModules.default` are aliases of the
same module.

## Configuration

All options live under `hardware.mnt-pocket-reform`:

| Option | Default | Purpose |
|---|---|---|
| `enable` | `false` | Enable the hardware support |
| `kernelPackages` | wrapped `pkgs.linuxPackages_latest` | Kernel used by the system; the default injects the MNT DTB |
| `panel.enable` | `true` | Build and load the panel driver |
| `systemController.enable` | `true` | Build and load `mnt_sc` |
| `wifi.enable` | `true` | Build `qcacld2`, install its firmware and blacklist `ath10k_sdio` |
| `debug` | `false` | Add `loglevel=7` and `no_console_suspend` kernel parameters |
| `bootloader.enable` | `true` | Install the generated `boot.scr` and `installBootLoader` script |
| `bootloader.device` | `"mmc 0:1"` | U-Boot device/partition holding `/boot` |
| `bootloader.kernelAddress` | `"0x40480000"` | Kernel load address |
| `bootloader.fdtAddress` | `"0x50000000"` | DTB load address |
| `bootloader.initrdAddress` | `"0x58000000"` | initrd load address |
| `bootloader.removeExtlinux` | `true` | Remove `/boot/extlinux` after writing `boot.scr` |

Set `hardware.mnt-pocket-reform.bootloader.device = "mmc 1:1"` (or the
matching device) if `/boot` is on the eMMC instead of the microSD.

## Boot layout

The Pocket Reform's U-Boot lives in the eMMC boot partition and its default
`boot_targets` are `mmc0 mmc2 usb0` (microSD, eMMC, USB). It **does not scan
the NVMe**. Therefore `/boot` must be on the microSD or eMMC, not on the NVMe.

Recommended layout:

```
microSD p1 : /boot (ext4, label NIXOS_BOOT)
NVMe p1    : LUKS2 -> btrfs -> root / nix / persistent
eMMC       : untouched Debian installation (fallback)
```

## LUKS key

The module does not hard-code a LUKS key. Configure it in the host, e.g. a key
file on the microSD `/boot` partition (mounted by the initrd):

```nix
boot.initrd.luks.devices."root_vg_pocket-reform".keyFile = "/boot/luks.key";
fileSystems."/boot".neededForBoot = true;
```

Add the key to the LUKS device with `cryptsetup luksAddKey` and keep the
passphrase in another slot as a recovery method.

## Kernel and modules

The default `hardware.mnt-pocket-reform.kernelPackages` wraps
`pkgs.linuxPackages_latest` (Linux 7.3.x at the time of writing) instead of the
MNT 6.19.6 kernel tree. The MNT kernel config builds around 7,500 modules and
takes many hours on the 4-core i.MX8MP; the nixpkgs kernel is already in the
binary cache. Override the option only with a kernel that also exposes a
`dtbs` output.

The missing MNT pieces are provided out-of-tree:

- `panel-mnt-pocket-reform` (ported to `devm_drm_panel_alloc`),
- `mnt_sc` (`system-controller/` in `reform-tools`, using the 7.3
  `power_supply_config.fwnode` API),
- `qcacld2` (Linux 7.3 `cfg80211` callback changes; P2P ops disabled).

All enabled modules are signed with `kmodigest`, as required by the NixOS 26.11
kernel-modules certificate aggregation. `mnt_sc` falls back to the `qcacld2`
certificate when `kmodigest` does not create one; if `wifi.enable = false`,
that fallback is unavailable and the build fails instead of silently
installing an unsigned module.

## System controller

The Pocket Reform's system controller is an RP2040 running MNT's
[`pocket-reform-sysctl-fw`](https://source.mnt.re/reform/pocket-reform). It
speaks the **s-expression** protocol (`(0q)`, `(0c)`, `(set-lite N)`,
`(soc-susp)`, ...) and drops the binary `0xb5` "LPC" header of the original
Reform. The DTS therefore declares `compatible = "mntre,system-controller"`
and the module loads `mnt_sc`.

Using `reform2_lpc` instead makes every SPI read return zeroes, because the
SC never answers the LPC protocol. The driver then clamps the gauge to 6%
(its floor, to avoid triggering UPower's emergency shutdown) and reports
`voltage_now = 0`, so e.g. noctalia/waybar show a battery stuck at 6% and a
bogus charging state even when the pack is full.

Verify with:

```bash
cat /sys/class/power_supply/BAT0/capacity   # real percentage
cat /sys/bus/spi/devices/spi1.0/status      # "8.3V -0.7A 95% [status=0] [API=4]"
```

`mnt_sc` also exposes the SC GPIOs (`disp_reset`, `hub_pwr_en`,
`pcie_pwr_en`, `3v3_en`, `uswitch_off`, `disp_bl_pwr_en`) and, when the DTS
declares the optional `backlight` child node, registers the SC PWM backlight
plus a suspend notifier that powers down the auxiliary rails with
`(soc-susp)`/`(soc-psus)`.

## Notes

- Do not write to `/dev/mmcblk2boot0` (the U-Boot boot partition) unless you
  have a backup and a recovery method.
- The nixpkgs kernel is cached, but the enabled out-of-tree modules are not;
  the first build takes roughly 15–30 minutes on the Pocket.
- The kernel-out wrapper only exposes the MNT DTB in `dtbs`; the extlinux
  builder only needs that DTB for this machine.
- `nix flake check` builds the DTB and firmware packages; `nix develop` provides
  `dtc`, `nixfmt` and `ubootTools`.
