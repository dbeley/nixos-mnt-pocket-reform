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

  # Empirically checked against the firmware: the LRGB payload is
  # (blue, green, red) — its led_set_rgb() builds the WS2812 frame as
  # buffer[6]<<16 | buffer[5]<<8 | buffer[4], so the first byte ends up on
  # the blue LEDs, not the red ones.
  colorR = builtins.substring 0 2 color;
  colorG = builtins.substring 2 2 color;
  colorB = builtins.substring 4 2 color;

  # `printf '\xNN'` needs one byte per component, `lib.toHexString` returns
  # unpadded uppercase hex without a prefix.
  hexByte =
    n:
    let
      h = lib.toHexString n;
    in
    if builtins.stringLength h == 1 then "0${h}" else h;

  # Keyboard firmware commands (see pocket-reform-keyboard-fw,
  # pocket-hid/src/main.c): a HID output report whose ID is 'x' followed by a
  # 4 character command. `LRGB` takes 3 raw bytes (r, g, b) and sets a uniform
  # backlight colour; `LBRT` takes 1 byte of brightness.
  #
  # The firmware hardcodes KBD_DEFAULT_BACKLIGHT_COLOR (0x200020) and applies
  # it when the keyboard powers up, so the colour has to be sent again on
  # every (re)enumeration.
  script = pkgs.writeShellApplication {
    name = "mnt-pocket-reform-kbd-backlight";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      # Find the keyboard by USB vendor/product id instead of by product
      # string: the hidraw by-id symlink is named after the USB product
      # string, which changed from "Pocket Reform Input 1.0" to "... 2.0".
      found=0
      for sys in /sys/class/hidraw/hidraw*; do
        [ -r "$sys/device/uevent" ] || continue
        grep -qi 'HID_ID=.*:00001209:00006D06' "$sys/device/uevent" || continue
        dev="/dev/''${sys##*/}"
        [ -c "$dev" ] || continue
        printf 'xLRGB\x${colorB}\x${colorG}\x${colorR}' > "$dev"
        printf 'xLBRT\x${hexByte kbd.brightness}' > "$dev"
        found=1
      done
      if [ "$found" -eq 0 ]; then
        echo "MNT Pocket Reform keyboard not found, leaving the backlight alone" >&2
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
        Uniform backlight colour as `#rrggbb`. The firmware otherwise uses its
        hardcoded default (`0x200020`, a dim purple), which it re-applies every
        time the keyboard powers up; this module re-sends the colour on each
        (re)enumeration of the keyboard.
      '';
    };

    brightness = lib.mkOption {
      type = lib.types.ints.between 0 150;
      default = 150;
      description = ''
        Backlight brightness, applied after the colour. The firmware caps it at
        `0x96` (150); a colour whose largest RGB component is above that value
        would otherwise light the LEDs brighter than the firmware's own maximum.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && kbd.enable && kbd.color != null) {
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="6d06", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-pocket-reform-kbd-backlight.service"
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
