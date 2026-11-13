{
  stdenv,
  lib,
  fetchzip,
  dtc,
}:
let
  # The MNT DTS includes the i.MX8MP dtsi files from the kernel tree. The
  # nixpkgs kernel dev output only ships headers, not the full dtsi files,
  # so use the matching upstream kernel source for the includes. Keep this
  # in sync with `pkgs.linuxPackages_latest.kernel.version`.
  mntSource = fetchzip {
    url = "mirror://kernel/linux/kernel/v7.x/linux-7.3.4.tar.xz";
    hash = "sha256-2q+CPRxgupua+EC7Smr0EUQCS2AFyZWGBd7oDM/vjmM=";
  };
in
stdenv.mkDerivation {
  pname = "mnt-pocket-dtb";
  version = "7.3.4";

  src = ./mnt-pocket-dtb;
  nativeBuildInputs = [ dtc ];

  buildPhase = ''
    runHook preBuild
    KSRC=${mntSource}
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
