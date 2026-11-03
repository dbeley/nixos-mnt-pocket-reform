{ nixos-hardware }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.mnt-pocket-reform;

  # The nixpkgs kernel is already built and cached for aarch64. The MNT
  # 6.19.6 kernel config builds ~7500 modules and takes many hours on the
  # 4-core i.MX8MP, so we use the nixpkgs kernel and provide the missing
  # MNT pieces (DTB, panel driver, system controller, Wi-Fi) out-of-tree.
  baseKernel = pkgs.linuxPackages_latest.kernel;

  mntDtb = pkgs.callPackage ../packages/mnt-pocket-dtb.nix { };

  panel = pkgs.callPackage ../packages/panel-mnt-pocket-reform.nix {
    kernel = baseKernel;
  };

  qcacld2 = pkgs.callPackage ../packages/qcacld2.nix {
    kernel = baseKernel;
  };

  lpc = pkgs.callPackage ../packages/lpc.nix {
    kernel = baseKernel;
    inherit qcacld2;
  };

  # Add the MNT DTB to the kernel's out output (the extlinux builder reads
  # $kernel/dtbs) without rebuilding the kernel itself.
  kernelOut = pkgs.runCommand "linux-7.3-mnt-pocket-out" { } ''
    mkdir -p $out
    for f in ${baseKernel.out}/*; do
      [ "$(basename "$f")" = dtbs ] && continue
      cp -rs "$f" $out/
    done
    mkdir -p $out/dtbs/freescale
    install -Dm644 ${mntDtb}/imx8mp-mnt-pocket-reform.dtb \
      $out/dtbs/freescale/imx8mp-mnt-pocket-reform.dtb
  '';

  kernelWithDtb = kernelOut
    // (builtins.removeAttrs baseKernel [
      "out"
      "outPath"
      "drvPath"
      "type"
      "outputs"
      "outputName"
      "override"
      "overrideAttrs"
      "overrideDerivation"
    ])
    // {
      mntPocketKernelWrapper = true;
      # NixOS calls kernel.override() to inject randstructSeed. The kernel is
      # prebuilt and cached; keep the wrapper instead of rebuilding it.
      override = _args: kernelWithDtb;
    };

  kernelPackages = pkgs.linuxPackagesFor kernelWithDtb;
in
{
  options.hardware.mnt-pocket-reform = {
    enable = lib.mkEnableOption "MNT Pocket Reform with i.MX8MP hardware support";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      # Override the global `linuxPackages_latest` with the wrapped kernel
      # (same kernel, dtbs output extended with the MNT DTB).
      kernelPackages = lib.mkForce kernelPackages;

      extraModulePackages = [
        panel
        lpc
        qcacld2
      ];

      kernelModules = [
        "panel-mnt-pocket-reform"
        "reform2_lpc"
        "qcacld2"
      ];
      blacklistedKernelModules = [ "ath10k_sdio" ];

      kernelParams = [
        "console=tty1"
        "fbcon=font:TER16x32"
        "cma=256MB"
        "pci=pcie_bus_perf"
        "nvme_core.default_ps_max_latency_us=0"
        "pcie_aspm=off"
        "no_console_suspend"
        "loglevel=7"
      ];

      initrd = {
        systemd.contents = {
          # Make sure the initrd root has the directories needed by the
          # rolling-root/impermanence initrd service and the fstab mounts.
          "/root/.keep".text = "";
        };

        # Boot-critical modules: NVMe + LUKS + btrfs + USB keyboard.
        kernelModules = [
          "nvme"
          "nvme_core"
          "dm_mod"
          "dm_crypt"
          "btrfs"
          "ext4"
          "mmc_block"
          "sdhci"
          "sdhci-esdhc-imx"
          "usbhid"
          # Force the internal panel/backlight to come up before
          # systemd-cryptsetup asks for the LUKS passphrase.
          "panel-mnt-pocket-reform"
          "imx-lcdif"
          "samsung_dsim"
          "pwm_imx27"
          "pwm_bl"
          "backlight"
        ];

        # Display modules are loaded by udev in stage 2; the temporary LUKS
        # key means the first boot does not depend on them.
        availableKernelModules = [
          # Needed early so the internal panel and backlight are up when
          # systemd-cryptsetup asks for the LUKS passphrase in the initrd.
          "panel-mnt-pocket-reform"
          "reform2_lpc"
          "imx-lcdif"
          "samsung_dsim"
          "pwm_imx27"
          "pwm_bl"
          "backlight"
          "mux_mmio"
          "mux_gpio"
          "gpio"
          "i2c-imx"
          "fan53555"
          "i2c_mux_pca954x"
          "imx_bus"
          "imx8mp-interconnect"
          "mxsfb"
          "usb_storage"
          "sd_mod"
        ];
      };

      loader = {
        grub.enable = false;
        systemd-boot.enable = false;
        limine.enable = false;
        efi.canTouchEfiVariables = false;

        generic-extlinux-compatible = {
          enable = true;
          configurationLimit = 2;
        };

        timeout = 2;
      };
    };

    # The MNT U-Boot defaults (fdt_addr_r=0x43000000 and
    # ramdisk_addr_r=0x43800000) overlap the ~70 MB NixOS kernel loaded at
    # kernel_addr_r=0x40480000. Its extlinux loader corrupts the kernel/initrd
    # and U-Boot falls back to the eMMC. Install a U-Boot script that loads
    # everything at safe addresses; regenerate it on every install/rebuild so
    # `nixos-rebuild boot/switch` and `nixos-install` always point at the
    # current generation.
    system.build.installBootLoader = lib.mkForce (pkgs.writeScript "install-pocket-bootloader" ''
      #!${pkgs.runtimeShell}
      set -euo pipefail
      export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnused pkgs.ubootTools ]}
      target="$1"

      # Copy kernel/initrd/DTB to /boot/nixos and write extlinux.conf.
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -d /boot -c "$target"

      kernel=$(readlink -f "$target/kernel")
      initrd=$(readlink -f "$target/initrd")
      dtbs=$(readlink -f "$target/dtbs")
      clean_name() { printf '%s' "$1" | sed 's|^/nix/store/||; s|/|-|g'; }

      cat > /boot/boot.cmd <<EOF
      setenv bootargs "init=$target/init $(cat "$target/kernel-params")"
      setenv fdt_addr_r 0x50000000
      setenv ramdisk_addr_r 0x58000000
      load mmc 0:1 0x40480000 /nixos/$(clean_name "$kernel")
      load mmc 0:1 0x50000000 /nixos/$(clean_name "$dtbs")/${config.hardware.deviceTree.name}
      load mmc 0:1 0x58000000 /nixos/$(clean_name "$initrd")
      booti 0x40480000 0x58000000:\''${filesize} 0x50000000
      EOF

      ${pkgs.ubootTools}/bin/mkimage -A arm64 -O linux -T script -C none \
        -d /boot/boot.cmd /boot/boot.scr
      rm -f /boot/boot.cmd
      # The extlinux path is unusable with this U-Boot; boot.scr is the entry
      # point. Keeping the directory would only add a failed attempt per boot.
      rm -rf /boot/extlinux
    '');

    hardware = {
      deviceTree.name = "freescale/imx8mp-mnt-pocket-reform.dtb";
      firmware = [ (pkgs.callPackage ../packages/qcacld2-firmware.nix { }) ];
      enableRedistributableFirmware = true;
      graphics.enable = true;
    };

  };
}
