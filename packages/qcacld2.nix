{
  stdenv,
  lib,
  fetchgit,
  kernel,
}:
stdenv.mkDerivation {
  pname = "qcacld2";
  version = "5ed82051e9fa391448e5805d1f1a5407c5890323";

  src = fetchgit {
    url = "https://source.mnt.re/reform/qcacld2.git";
    rev = "5ed82051e9fa391448e5805d1f1a5407c5890323";
    hash = "sha256-mL+t1i9fscqBB65TAJPq7ekkeHEOBAsgXgFyFcECgaA=";
  };

  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "MODNAME=qcacld2"
    "CONFIG_CLD_HL_SDIO_CORE=y"
    "CONFIG_FORCE_MLO_SUPPORT=y"
    "KERNELRELEASE=${kernel.modDirVersion}"
    "KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
    cp *.ko $out/lib/modules/${kernel.modDirVersion}/extra/
    runHook postInstall
  '';

  meta = with lib; {
    description = "MNT Reform Qualcomm Atheros qcacld2 WLAN driver";
    homepage = "https://source.mnt.re/reform/qcacld2";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
