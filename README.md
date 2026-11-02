# nixos-mnt-pocket-reform

NixOS hardware support for the **MNT Pocket Reform with the i.MX8MP module**.

This flake provides a NixOS module that adds:

- the MNT-patched Linux kernel (via `nixos-hardware`'s `mnt-reform` module),
- the `reform2_lpc` system-controller driver (battery, backlight, GPIO),
- the `qcacld2` out-of-tree Wi-Fi driver and firmware for the QCA9377 SDIO module,
- the correct device tree (`freescale/imx8mp-mnt-pocket-reform.dtb`),
- kernel parameters and initrd modules for the internal display, NVMe, SD and USB keyboard,
- a generic-extlinux-compatible boot configuration.

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
          boot.loader.generic-extlinux-compatible.configurationLimit = 2;
        }
        ./configuration.nix
      ];
    };
  };
}
```

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

## Temporary LUKS key

For the first boot (when the display may not work yet), the module can embed a
temporary key file in the initrd:

```nix
hardware.mnt-pocket-reform.temporaryLuksKeyFile = /path/to/luks.key;
```

Remove this option and rebuild once the system has been validated. The key
file must also be added to the LUKS device with `cryptsetup luksAddKey`.

## Kernel choice

The module currently uses the kernel from `nixos-hardware` (`mnt-reform`,
Linux 6.19.x at the time of writing). A future version may switch to the MNT
Linux 7.2.x tree with the in-tree `mnt-sc` driver.

## Notes

- Do not write to `/dev/mmcblk2boot0` (the U-Boot boot partition) unless you
  have a backup and a recovery method.
- The MNT kernel and the qcacld2/LPC modules are not in a binary cache, so the
  first build takes a while.
