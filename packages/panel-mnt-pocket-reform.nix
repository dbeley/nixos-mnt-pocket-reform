{
  stdenv,
  lib,
  kernel,
  kmodigest,
}:
stdenv.mkDerivation {
  pname = "panel-mnt-pocket-reform";
  version = "6.19.6";

  src = ./panel-mnt-pocket-reform/src;
  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
    cp *.ko $out/lib/modules/${kernel.modDirVersion}/extra/
    runHook postInstall
  '';

  postInstall = ''
    for module in $out/lib/modules/${kernel.modDirVersion}/extra/*.ko; do
      ${lib.getExe kmodigest} "$module"
    done
  '';

  meta = with lib; {
    description = "MNT Pocket Reform JDI LT070ME05000 panel driver";
    homepage = "https://source.mnt.re/reform/reform-debian-packages";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
