{
  stdenvNoCC,
  lib,
  fetchgit,
}:
let
  pin = import ./qcacld2-pin.nix;
in
stdenvNoCC.mkDerivation {
  pname = "qcacld2-firmware";
  version = pin.rev;

  src = fetchgit {
    inherit (pin) url rev hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontPatch = true;
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/lib/firmware/qcacld2 $out/lib/firmware/wlan/qcacld2

    cp debian/bdwlan30.bin debian/otp30.bin debian/qwlan30.bin \
      $out/lib/firmware/qcacld2/

    cp debian/cfg.dat debian/qcom_cfg.ini \
      $out/lib/firmware/qcacld2/
    cp debian/cfg.dat debian/qcom_cfg.ini \
      $out/lib/firmware/wlan/qcacld2/
  '';

  meta = with lib; {
    description = "Firmware for the MNT Reform QCA9377 qcacld2 WLAN module";
    homepage = "https://source.mnt.re/reform/qcacld2";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux;
  };
}
