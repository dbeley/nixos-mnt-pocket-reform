# SPDX-License-Identifier: GPL-3.0-only

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.mnt-pocket-reform;
  kbd = cfg.keyboardBacklight;
  firmware = kbd.firmware;

  # 6 hex digits, no leading '#'.
  color = lib.removePrefix "#" kbd.color;

  # Backlight colour as three 0-255 bytes. QMK takes RGB in the natural order
  # (it converts to HSV and hands it to rgblight). The stock firmware's LRGB
  # payload is (blue, green, red) instead.
  colorR = lib.fromHexString (builtins.substring 0 2 color);
  colorG = lib.fromHexString (builtins.substring 2 2 color);
  colorB = lib.fromHexString (builtins.substring 4 2 color);

  # QMK reserves 0xFF for "keep the current brightness"; only an explicit
  # option value overrides it. The option's scale is the stock firmware's
  # (0-150); QMK's value is 0-255, but 150 maps to 254 to avoid the sentinel.
  qmkBrightness = if kbd.brightness == null then 255 else lib.min 254 (kbd.brightness * 255 / 150);

  # The stock firmware has no "keep" command, so null means its maximum.
  stockBrightness = if kbd.brightness == null then 150 else kbd.brightness;

  # QMK raw HID: a single 32-byte output report, no report id.
  #   byte 0: 'C', bytes 1-3: r,g,b, byte 4: value (0xFF = keep), rest unused.
  # See pocket_backlight.c in qmk-config for the receiving side.
  # 67 is 'C', the "set colour" command.
  qmkReportBytes = [
    67
    colorR
    colorG
    colorB
    qmkBrightness
  ]
  ++ (lib.replicate 27 0);

  # Bash cannot hold NUL bytes in a string, but printf resolves these escapes
  # while writing, so the frame goes out in a single 32-byte write().
  hexByte =
    n:
    let
      h = lib.toHexString n;
    in
    if builtins.stringLength h == 1 then "0${h}" else h;
  qmkReport = lib.concatMapStrings (b: "\\x${hexByte b}") qmkReportBytes;

  # Stock firmware HID commands (pocket-reform-keyboard-fw): an output report
  # starting with 'x' followed by a 4-character command. LRGB takes (blue,
  # green, red) and LBRT one brightness byte. LRGB resets the brightness to the
  # colour's own value, so LBRT has to follow it.
  stockColorReport = "xLRGB\\x${hexByte colorB}\\x${hexByte colorG}\\x${hexByte colorR}";
  stockBrightnessReport = "xLBRT\\x${hexByte stockBrightness}";

  # USB ids used to tell the two firmwares apart and to trigger the service.
  stockVendor = "1209";
  stockProduct = "6d06";
  qmkVendor = "feed";
  qmkProduct = "0000";

  sendStock = firmware == "auto" || firmware == "stock";
  sendQmk = firmware == "auto" || firmware == "qmk";

  # The colour has to be re-sent on every (re)enumeration, because the stock
  # firmware re-applies its hardcoded default and QMK restores its own EEPROM
  # state when the keyboard powers up.
  #
  # hidraw nodes do not expose the HID usage page, so write to every matching
  # node: the keyboard and mouse interfaces have no output report and reject
  # it, while the raw HID interface accepts it.
  script = pkgs.writeShellApplication {
    name = "mnt-pocket-reform-kbd-backlight";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      target=${lib.escapeShellArg firmware}
      found_stock=0
      found_qmk=0
      for sys in /sys/class/hidraw/hidraw*; do
        [ -r "$sys/device/uevent" ] || continue
        dev="/dev/''${sys##*/}"
        [ -c "$dev" ] || continue

        if grep -qi 'HID_ID=.*:0000${stockVendor}:0000${stockProduct}' "$sys/device/uevent"; then
          if [ "$target" = "qmk" ]; then
            continue
          fi
          if printf '${stockColorReport}' > "$dev" 2>/dev/null; then
            printf '${stockBrightnessReport}' > "$dev" 2>/dev/null || true
            found_stock=1
          fi
          continue
        fi

        if grep -qi 'HID_ID=.*:0000${qmkVendor}:0000${qmkProduct}' "$sys/device/uevent"; then
          if [ "$target" = "stock" ]; then
            continue
          fi
          if printf '${qmkReport}' > "$dev" 2>/dev/null; then
            found_qmk=1
          fi
          continue
        fi
      done

      if [ "$found_stock" -eq 0 ] && [ "$found_qmk" -eq 0 ]; then
        case "$target" in
          stock) echo "MNT Pocket Reform keyboard (original firmware) not found, leaving the backlight alone" >&2 ;;
          qmk) echo "MNT Pocket Reform keyboard (QMK raw HID) not found, leaving the backlight alone" >&2 ;;
          auto) echo "MNT Pocket Reform keyboard (original or QMK firmware) not found, leaving the backlight alone" >&2 ;;
        esac
      fi
    '';
  };
in
{
  options.hardware.mnt-pocket-reform.keyboardBacklight = {
    enable = lib.mkEnableOption "setting the keyboard RGB backlight colour from userspace";

    firmware = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "stock"
        "qmk"
      ];
      default = "auto";
      description = ''
        Keyboard firmware variant. `auto` detects the original MNT firmware
        (USB `1209:6d06`) or QMK (USB `FEED:0000`) from the hidraw node's USB
        id. Set `stock` or `qmk` to force one protocol if autodetection is
        ambiguous.
      '';
    };

    color = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "#?[0-9a-fA-F]{6}");
      default = null;
      example = "#8f88d5";
      description = ''
        Uniform backlight colour as `#rrggbb`. The original firmware hardcodes
        its default and QMK keeps its own rgb state in EEPROM, so this module
        re-sends the colour on each (re)enumeration of the keyboard.
      '';
    };

    brightness = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 0 150);
      default = null;
      description = ''
        Backlight brightness. For QMK, leave it `null` (the default) to let the
        keyboard keep whatever brightness it has: the trackball sets it while
        HYPER is held, and the firmware stores it in EEPROM, so overriding it
        here would undo those adjustments on every re-enumeration. The original
        firmware has no "keep" command, so `null` sends its maximum (`150`)
        there. Kept on the original firmware's 0-150 scale and rescaled to
        QMK's 0-254 range when set (`150` maps to `254`, because `255` means
        "keep"). `0` turns the backlight off.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && kbd.enable && kbd.color != null) {
    services.udev.extraRules =
      lib.optionalString sendStock ''
        ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${stockVendor}", ATTRS{idProduct}=="${stockProduct}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-pocket-reform-kbd-backlight.service"
      ''
      + lib.optionalString sendQmk ''
        ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${qmkVendor}", ATTRS{idProduct}=="${qmkProduct}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-pocket-reform-kbd-backlight.service"
      '';

    systemd.services.mnt-pocket-reform-kbd-backlight = {
      description = "Set the MNT Pocket Reform keyboard backlight colour";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Re-run on every udev `add` event, including replugs after boot.
        RemainAfterExit = false;
        ExecStart = lib.getExe script;
      };
      # Re-run on `nixos-rebuild switch` when the colour changes.
      restartTriggers = [ script ];
    };
  };
}
