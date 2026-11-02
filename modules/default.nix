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

    temporaryLuksKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
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
        # The crypttab references this key path, so the key file must be
        # copied into the initrd; otherwise the LUKS device is never opened.
        # `null` means "same path inside and outside the initrd". Using
        # `/. + path` would make evaluation impure; `null` lets the
        # bootloader installer read the host file when it appends secrets.
        secrets = lib.mkIf (cfg.temporaryLuksKeyFile != null) {
          "${cfg.temporaryLuksKeyFile}" = null;
        };

        # nixos-init/initrd-init mounts the fstab on /root; the mount point
        # must exist in the initrd.
        systemd.contents."/root/.keep".text = "";

        # Boot-critical modules: NVMe + LUKS + btrfs + USB keyboard.
        kernelModules = [
          "nvme"
          "nvme_core"
          "dm_mod"
          "dm_crypt"
          "btrfs"
          "ext4"
          "mmc_block"
          "usbhid"
        ];

        # Display modules are loaded by udev in stage 2; the temporary LUKS
        # key means the first boot does not depend on them.
        availableKernelModules = [
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
