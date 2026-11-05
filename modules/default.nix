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
  baseKernelPackages = pkgs.linuxPackages_latest;
  baseKernel = baseKernelPackages.kernel;

  mntDtb = pkgs.callPackage ../packages/mnt-pocket-dtb.nix { };

  # Add the MNT DTB to the kernel's out output (the extlinux builder reads
  # $kernel/dtbs) without rebuilding the kernel itself.
  kernelOut = pkgs.runCommand "linux-${baseKernel.version}-mnt-pocket-out" { } ''
    mkdir -p $out
    for f in ${baseKernel.out}/*; do
      [ "$(basename "$f")" = dtbs ] && continue
      cp -rs "$f" $out/
    done
    mkdir -p $out/dtbs/freescale
    install -Dm644 ${mntDtb}/imx8mp-mnt-pocket-reform.dtb \
      $out/dtbs/freescale/imx8mp-mnt-pocket-reform.dtb
  '';

  kernelWithDtb =
    kernelOut
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

  defaultKernelPackages = pkgs.linuxPackagesFor kernelWithDtb;

  kernel = cfg.kernelPackages.kernel;

  panel = pkgs.callPackage ../packages/panel-mnt-pocket-reform.nix {
    inherit kernel;
  };

  qcacld2 = pkgs.callPackage ../packages/qcacld2.nix {
    inherit kernel;
  };

  # The Pocket Reform's system controller (RP2040) speaks the s-expression
  # protocol implemented by `mnt_sc`, not the binary "LPC" protocol of the
  # original Reform. `reform2_lpc` binds to the same SPI device and then
  # reads zeroes for every command, which surfaces as a battery stuck at
  # 6% (the driver clamps 0) and a bogus charging state.
  mntSc = pkgs.callPackage ../packages/mnt-sc.nix {
    inherit kernel;
    # `mnt_sc` reuses the qcacld2 certificate when kmodigest does not
    # produce one. Pass null when the Wi-Fi driver is disabled.
    qcacld2 = if cfg.wifi.enable then qcacld2 else null;
  };

  qcacld2Firmware = pkgs.callPackage ../packages/qcacld2-firmware.nix { };
in
{
  imports = [ ./audio.nix ];

  options.hardware.mnt-pocket-reform = {
    enable = lib.mkEnableOption "MNT Pocket Reform with i.MX8MP hardware support";

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = defaultKernelPackages;
      defaultText = lib.literalMD "wrapped `pkgs.linuxPackages_latest` with the MNT DTB";
      description = ''
        Kernel package set used by the Pocket Reform. The default wraps the
        nixpkgs `linuxPackages_latest` kernel and injects the MNT DTB into its
        `dtbs` output without rebuilding the kernel. Override this only with a
        kernel that provides the same DTB layout.
      '';
    };

    panel.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the MNT Pocket Reform panel driver.";
    };

    systemController.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the MNT system controller (`mnt_sc`) driver.";
    };

    wifi.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the `qcacld2` Wi-Fi driver and firmware.";
    };

    debug = lib.mkEnableOption "verbose kernel logging and `no_console_suspend` for bring-up";

    power = {
      cmaSize = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "256MB";
        description = ''
          Value of the `cma=` kernel parameter. `null` omits the parameter and
          leaves the kernel default. Lower it to free RAM when the panel and
          VPU do not need the full contiguous allocation.
        '';
      };

      nvmePsMaxLatencyUs = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = 0;
        description = ''
          Value of `nvme_core.default_ps_max_latency_us`. `0` disables NVMe
          APST; `null` omits the parameter and uses the kernel default. Set a
          positive value (for example `100000`) to keep APST with a latency
          cap.
        '';
      };

      pcieAspm = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "off"
            "force"
          ]
        );
        default = "off";
        description = ''
          Value of the `pcie_aspm=` kernel parameter. `null` omits it and lets
          the platform/firmware policy apply.
        '';
      };

      pcieAspmPolicy = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "default"
            "performance"
            "powersave"
            "powersupersave"
          ]
        );
        default = null;
        description = ''
          Value of the `pcie_aspm.policy=` kernel parameter. Only effective
          when ASPM is enabled, i.e. when `pcieAspm` is not `"off"`.
        '';
      };
    };

    initrd = {
      luks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Include `dm_mod` and `dm_crypt` in the initrd. Enable this when the
          root filesystem is on LUKS; disable it for a plain root to keep the
          initrd smaller.
        '';
      };

      btrfs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Include the `btrfs` module in the initrd. Disable it when the root
          filesystem is not btrfs.
        '';
      };
    };

    bootloader = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the Pocket Reform U-Boot boot script. Disable this if you
          manage `/boot` and the bootloader yourself.
        '';
      };

      device = lib.mkOption {
        type = lib.types.str;
        default = "mmc 0:1";
        description = "U-Boot device and partition containing `/boot`.";
        example = "mmc 1:1";
      };

      kernelAddress = lib.mkOption {
        type = lib.types.str;
        default = "0x40480000";
        description = "U-Boot load address for the kernel.";
      };

      fdtAddress = lib.mkOption {
        type = lib.types.str;
        default = "0x50000000";
        description = "U-Boot load address for the device tree.";
      };

      initrdAddress = lib.mkOption {
        type = lib.types.str;
        default = "0x58000000";
        description = "U-Boot load address for the initrd.";
      };

      removeExtlinux = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Remove `/boot/extlinux` after installing the boot script. This
          U-Boot's extlinux loader corrupts the kernel/initrd, so the
          directory only adds a failed boot attempt.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "hardware.mnt-pocket-reform currently supports aarch64-linux only.";
      }
    ];

    boot = {
      # Use the wrapped kernel (same kernel, dtbs output extended with the
      # MNT DTB). `mkForce` is intentional: a global `boot.kernelPackages`
      # definition (common in shared configurations) would otherwise drop the
      # DTB wrapper. Override `hardware.mnt-pocket-reform.kernelPackages`
      # instead.
      kernelPackages = lib.mkForce cfg.kernelPackages;

      extraModulePackages =
        lib.optional cfg.panel.enable panel
        ++ lib.optional cfg.systemController.enable mntSc
        ++ lib.optional cfg.wifi.enable qcacld2;

      kernelModules =
        lib.optional cfg.panel.enable "panel-mnt-pocket-reform"
        ++ lib.optional cfg.systemController.enable "mnt_sc"
        ++ lib.optional cfg.wifi.enable "qcacld2";

      blacklistedKernelModules = lib.optional cfg.wifi.enable "ath10k_sdio";

      kernelParams = [
        "console=tty1"
        "fbcon=font:TER16x32"
        "pci=pcie_bus_perf"
      ]
      ++ lib.optional (cfg.power.cmaSize != null) "cma=${cfg.power.cmaSize}"
      ++ lib.optional (
        cfg.power.nvmePsMaxLatencyUs != null
      ) "nvme_core.default_ps_max_latency_us=${toString cfg.power.nvmePsMaxLatencyUs}"
      ++ lib.optional (cfg.power.pcieAspm != null) "pcie_aspm=${cfg.power.pcieAspm}"
      ++ lib.optional (cfg.power.pcieAspmPolicy != null) "pcie_aspm.policy=${cfg.power.pcieAspmPolicy}"
      ++ lib.optionals cfg.debug [
        "no_console_suspend"
        "loglevel=7"
      ];

      initrd = {
        # Boot-critical modules: NVMe + optional LUKS/btrfs + USB keyboard.
        kernelModules = [
          "nvme"
          "nvme_core"
          "ext4"
          "mmc_block"
          "sdhci"
          "sdhci-esdhc-imx"
          "usbhid"
        ]
        ++ lib.optional cfg.initrd.luks "dm_mod"
        ++ lib.optional cfg.initrd.luks "dm_crypt"
        ++ lib.optional cfg.initrd.btrfs "btrfs"
        ++ lib.optionals cfg.panel.enable [
          # Force the internal panel/backlight to come up before
          # systemd-cryptsetup asks for the LUKS passphrase.
          "panel-mnt-pocket-reform"
          "imx-lcdif"
          "samsung_dsim"
          "pwm_imx27"
          "pwm_bl"
          "backlight"
        ];

        # Display modules are loaded by udev in stage 2; the initrd loads
        # them early so the LUKS passphrase prompt is visible on the
        # internal panel.
        availableKernelModules = [
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
        ]
        ++ lib.optionals cfg.panel.enable [
          "panel-mnt-pocket-reform"
          "imx-lcdif"
          "samsung_dsim"
          "pwm_imx27"
          "pwm_bl"
          "backlight"
        ]
        ++ lib.optional cfg.systemController.enable "mnt_sc";
      };

      loader = lib.mkIf cfg.bootloader.enable {
        grub.enable = lib.mkDefault false;
        systemd-boot.enable = lib.mkDefault false;
        limine.enable = lib.mkDefault false;
        efi.canTouchEfiVariables = lib.mkDefault false;

        generic-extlinux-compatible = {
          enable = lib.mkDefault true;
          configurationLimit = lib.mkDefault 2;
        };

        timeout = lib.mkDefault 2;
      };
    };

    # The MNT U-Boot defaults (fdt_addr_r=0x43000000 and
    # ramdisk_addr_r=0x43800000) overlap the ~70 MB NixOS kernel loaded at
    # kernel_addr_r=0x40480000. Its extlinux loader corrupts the kernel/initrd
    # and U-Boot falls back to the eMMC. Install a U-Boot script that loads
    # everything at safe addresses; regenerate it on every install/rebuild so
    # `nixos-rebuild boot/switch` and `nixos-install` always point at the
    # current generation.
    system.build.installBootLoader = lib.mkIf cfg.bootloader.enable (
      lib.mkForce (
        pkgs.writeScript "install-pocket-bootloader" ''
          #!${pkgs.runtimeShell}
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.gnused
              pkgs.ubootTools
            ]
          }
          target="$1"

          # Copy kernel/initrd/DTB to /boot/nixos and write extlinux.conf.
          ${config.boot.loader.generic-extlinux-compatible.populateCmd} -d /boot -c "$target"

          kernel=$(readlink -f "$target/kernel")
          initrd=$(readlink -f "$target/initrd")
          dtbs=$(readlink -f "$target/dtbs")
          clean_name() { printf '%s' "$1" | sed 's|^/nix/store/||; s|/|-|g'; }

          cat > /boot/boot.cmd <<EOF
          setenv bootargs "init=$target/init $(cat "$target/kernel-params")"
          setenv fdt_addr_r ${cfg.bootloader.fdtAddress}
          setenv ramdisk_addr_r ${cfg.bootloader.initrdAddress}
          load ${cfg.bootloader.device} ${cfg.bootloader.kernelAddress} /nixos/$(clean_name "$kernel")
          load ${cfg.bootloader.device} ${cfg.bootloader.fdtAddress} /nixos/$(clean_name "$dtbs")/${config.hardware.deviceTree.name}
          load ${cfg.bootloader.device} ${cfg.bootloader.initrdAddress} /nixos/$(clean_name "$initrd")
          booti ${cfg.bootloader.kernelAddress} ${cfg.bootloader.initrdAddress}:\''${filesize} ${cfg.bootloader.fdtAddress}
          EOF

          ${pkgs.ubootTools}/bin/mkimage -A arm64 -O linux -T script -C none \
            -d /boot/boot.cmd /boot/boot.scr
          rm -f /boot/boot.cmd
          # The extlinux path is unusable with this U-Boot; boot.scr is the entry
          # point. Keeping the directory would only add a failed attempt per boot.
          ${lib.optionalString cfg.bootloader.removeExtlinux "rm -rf /boot/extlinux"}
        ''
      )
    );

    hardware = {
      deviceTree.name = lib.mkDefault "freescale/imx8mp-mnt-pocket-reform.dtb";
      firmware = lib.mkIf cfg.wifi.enable [ qcacld2Firmware ];
      enableRedistributableFirmware = lib.mkDefault true;
      graphics.enable = lib.mkDefault true;
    };
  };
}
