{
  stdenv,
  lib,
  kernel,
  dtc,
}:
stdenv.mkDerivation {
  pname = "mnt-pocket-dtb";
  version = "6.19.6";

  src = ./mnt-pocket-dtb;
  nativeBuildInputs = [ dtc ];

  buildPhase = ''
    runHook preBuild
    KSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build
    cpp -nostdinc \
      -I$KSRC/include \
      -I$KSRC/arch/arm64/boot/dts \
      -I$KSRC/arch/arm64/boot/dts/freescale \
      -undef -D__DTS__ -x assembler-with-cpp \
      imx8mp-mnt-pocket-reform.dts -o preprocessed.dts
    dtc -I dts -O dtb -o imx8mp-mnt-pocket-reform.dtb preprocessed.dts
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp imx8mp-mnt-pocket-reform.dtb $out/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Device tree blob for the MNT Pocket Reform i.MX8MP";
    homepage = "https://source.mnt.re/reform/reform-debian-packages";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
