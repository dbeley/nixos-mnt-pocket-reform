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
  options.hardware.mnt-pocket-reform.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Initialise the tlv320aic3100 codec mixer at boot. Without it the
      speaker and the headphone jack stay silent, because the codec comes up
      with its output routing disabled and no ALSA UCM profile exists for
      this card.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.audio.enable) {
    # The tlv320aic3100 powers up with the DAC->output routing switches off,
    # the speaker driver disabled and its analog gain at -63.5 dB. Nothing
    # else initialises the mixer: there is no UCM profile for this card and
    # NixOS has no alsa-restore state, so the speaker is silent whatever the
    # PipeWire volume is.
    #
    # Same sequence as init_tlv320aic3100() in MNT's reform-tools
    # (bin/reform-hw-setup), which Debian runs for the i.MX8MP module.
    systemd.services.mnt-pocket-reform-audio = {
      description = "Initialise the MNT Pocket Reform tlv320aic3100 mixer";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.alsa-utils
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Wait for the codec card to be registered by udev, then look it up by
        # name: card 1 is the WWAN modem codec, which has nothing to do with
        # the speaker.
        i=0
        card=
        while [ -z "$card" ] && [ "$i" -lt 50 ]; do
          card=$(awk '/tlv320aic3100/ { print $1; exit }' /proc/asound/cards)
          [ -n "$card" ] || sleep 0.1
          i=$((i + 1))
        done
        if [ -z "$card" ]; then
          echo "tlv320aic3100 codec not found in /proc/asound/cards" >&2
          exit 1
        fi

        amixer -c "$card" sset 'Speaker Driver' on
        amixer -c "$card" sset 'Output Left From Left DAC' on
        amixer -c "$card" sset 'Output Right From Right DAC' on
        amixer -c "$card" sset 'Speaker Analog' 127
        amixer -c "$card" sset 'DAC' 127
        amixer -c "$card" sset 'HP Analog' 127
        amixer -c "$card" sset 'HP Driver' on
        amixer -c "$card" sset 'HP Left' on
        amixer -c "$card" sset 'HP Right' on
      '';
    };
  };
}
