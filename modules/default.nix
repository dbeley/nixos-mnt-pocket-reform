{ nixos-hardware }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.mnt-pocket-reform;
in
{
  imports = [ (import "${nixos-hardware}/mnt/reform") ];

  options.hardware.mnt-pocket-reform = {
    enable = lib.mkEnableOption "MNT Pocket Reform with i.MX8MP hardware support";

    temporaryLuksKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional temporary LUKS key file to embed in the initrd. This is
        intended for the first boot/debugging phase only; remove it and use a
        passphrase once the system is validated.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      # nixos-hardware's mnt-reform module provides the MNT kernel as mkDefault.
      # Force it so that a global `boot.kernelPackages = pkgs.linuxPackages_latest`
      # does not win.
      kernelPackages = lib.mkForce (
        pkgs.callPackage "${nixos-hardware}/mnt/reform/kernel.nix" { }
      );

      extraModulePackages = [
        (pkgs.callPackage ../packages/qcacld2.nix {
          kernel = config.boot.kernelPackages.kernel;
        })
      ];

      kernelModules = [ "qcacld2" ];
      blacklistedKernelModules = [ "ath10k_sdio" ];

      kernelParams = [
        "console=ttymxc1,115200"
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
        # Loaded early so the LUKS prompt is visible on the internal display.
        kernelModules = [
          "reset_imx7"
          "mux_mmio"
          "mux_gpio"
          "gpio"
          "fixed"
          "i2c-imx"
          "fan53555"
          "i2c_mux_pca954x"
          "imx_bus"
          "imx8mp-interconnect"
          "pwm_imx27"
          "pwm_bl"
          "nwl-dsi"
          "imx-dcss"
          "imx-lcdif"
          "samsung_dsim"
          "panel_mnt_pocket_reform"
          "mxsfb"
          "usbhid"
          "governor_userspace"
          "cpufreq_dt"
          "mmc_block"
          "nvme"
        ];

        availableKernelModules = [
          "ext4"
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

    hardware = {
      deviceTree.name = "freescale/imx8mp-mnt-pocket-reform.dtb";
      firmware = [ (pkgs.callPackage ../packages/qcacld2-firmware.nix { }) ];
      enableRedistributableFirmware = true;
      graphics.enable = true;
    };

    # Optional temporary key for the disko-created LUKS device.
    boot.initrd.luks.devices = lib.mkIf (cfg.temporaryLuksKeyFile != null) {
      "root_vg_pocket-reform".keyFile = cfg.temporaryLuksKeyFile;
    };
  };
}
