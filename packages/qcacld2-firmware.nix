{
  stdenvNoCC,
  lib,
  fetchgit,
}:
stdenvNoCC.mkDerivation {
  pname = "qcacld2-firmware";
  version = "5ed82051e9fa391448e5805d1f1a5407c5890323";

  src = fetchgit {
    url = "https://source.mnt.re/reform/qcacld2.git";
    rev = "5ed82051e9fa391448e5805d1f1a5407c5890323";
    hash = "sha256-mL+t1i9fscqBB65TAJPq7ekkeHEOBAsgXgFyFcECgaA=";
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
