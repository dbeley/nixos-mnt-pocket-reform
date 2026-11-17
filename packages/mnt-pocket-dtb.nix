{
  stdenv,
  lib,
  kernel,
  dtc,
  xz,
}:
stdenv.mkDerivation {
  pname = "mnt-pocket-dtb";
  version = kernel.version;

  src = ./mnt-pocket-dtb;
  nativeBuildInputs = [
    dtc
    xz
  ];

  buildPhase = ''
    runHook preBuild

    # The MNT DTS includes the i.MX8MP dtsi files from the kernel tree, but
    # the kernel's dev output only ships headers. Use the source of the very
    # kernel that loads the blob, so the includes cannot drift from it.
    mkdir -p kernel-source
    tar -xf ${kernel.src} -C kernel-source --strip-components=1
    KSRC=$PWD/kernel-source

    cpp -nostdinc \
      -I$PWD/include \
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
