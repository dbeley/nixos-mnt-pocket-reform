{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.mnt-pocket-reform;
  kbd = cfg.keyboardBacklight;

  # 6 hex digits, no leading '#'.
  color = lib.removePrefix "#" kbd.color;

  # Backlight colour as three 0-255 bytes. The QMK firmware takes RGB in the
  # natural order (it converts to HSV and hands it to rgblight), so no channel
  # swapping is needed, unlike the stock firmware's LRGB payload.
  colorR = lib.fromHexString (builtins.substring 0 2 color);
  colorG = lib.fromHexString (builtins.substring 2 2 color);
  colorB = lib.fromHexString (builtins.substring 4 2 color);

  # The option's scale is the stock firmware's (0-150); QMK's rgb value is
  # 0-255.
  value = kbd.brightness * 255 / 150;

  # QMK raw HID: a single 32-byte output report, no report id.
  #   byte 0: 'C', bytes 1-3: r,g,b, byte 4: value, rest unused.
  # See pocket_backlight.c in qmk-config for the receiving side.
  # 67 is 'C', the "set colour" command.
  reportBytes = [
    67
    colorR
    colorG
    colorB
    value
  ] ++ (lib.replicate 27 0);

  # Bash cannot hold NUL bytes in a string, but printf resolves these escapes
  # while writing, so the frame goes out in a single 32-byte write().
  hexByte =
    n:
    let
      h = lib.toHexString n;
    in
    if builtins.stringLength h == 1 then "0${h}" else h;
  report = lib.concatMapStrings (b: "\\x${hexByte b}") reportBytes;

  # QMK exposes the backlight control on a vendor raw HID interface, which is a
  # separate hidraw node whose vendor/product ids are the same as the
  # keyboard's (FEED:0000). udev does not expose the HID usage page for hidraw
  # nodes, so write the report to every matching node: the keyboard and mouse
  # interfaces have no output report and reject it.
  #
  # The colour has to be re-sent on every (re)enumeration, because the firmware
  # restores whatever rgb state it has in its own EEPROM when it powers up.
  script = pkgs.writeShellApplication {
    name = "mnt-pocket-reform-kbd-backlight";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      found=0
      for sys in /sys/class/hidraw/hidraw*; do
        [ -r "$sys/device/uevent" ] || continue
        grep -qi 'HID_ID=.*:0000FEED:00000000' "$sys/device/uevent" || continue
        dev="/dev/''${sys##*/}"
        [ -c "$dev" ] || continue
        if printf '${report}' > "$dev" 2>/dev/null; then
          found=1
        fi
      done
      if [ "$found" -eq 0 ]; then
        echo "MNT Pocket Reform keyboard (QMK raw HID) not found, leaving the backlight alone" >&2
      fi
    '';
  };
in
{
  options.hardware.mnt-pocket-reform.keyboardBacklight = {
    enable = lib.mkEnableOption "setting the keyboard RGB backlight colour from userspace";

    color = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "#?[0-9a-fA-F]{6}");
      default = null;
      example = "#8f88d5";
      description = ''
        Uniform backlight colour as `#rrggbb`. The firmware keeps its own rgb
        state in EEPROM, which may differ, so this module re-sends the colour on
        each (re)enumeration of the keyboard.
      '';
    };

    brightness = lib.mkOption {
      type = lib.types.ints.between 0 150;
      default = 150;
      description = ''
        Backlight brightness, applied after the colour. Kept on the stock
        firmware's 0-150 scale and rescaled to QMK's 0-255 before sending.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && kbd.enable && kbd.color != null) {
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="feed", ATTRS{idProduct}=="0000", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-pocket-reform-kbd-backlight.service"
    '';

    systemd.services.mnt-pocket-reform-kbd-backlight = {
      description = "Set the MNT Pocket Reform keyboard backlight colour";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe script;
      };
      # Re-run on `nixos-rebuild switch` when the colour changes.
      restartTriggers = [ script ];
    };
  };
}
