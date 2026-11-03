{
  stdenv,
  lib,
  fetchgit,
  kernel,
  kmodigest,
}:
let
  pin = import ./qcacld2-pin.nix;
in
stdenv.mkDerivation {
  pname = "qcacld2";
  version = pin.rev;

  src = fetchgit {
    inherit (pin) url rev hash;
  };

  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  postPatch = ''
    # Linux 7.3 changed the cfg80211 remain_on_channel/mgmt_tx cookie
    # arguments from u64* to u64. These ops are only needed for P2P/AP; the
    # driver is used in station mode, so leave them out instead of porting
    # the callbacks.
    sed -i '/\.remain_on_channel =/d; /\.mgmt_tx =/d' \
      CORE/HDD/src/wlan_hdd_cfg80211.c
  '';

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

  postInstall = ''
    for module in $out/lib/modules/${kernel.modDirVersion}/extra/*.ko; do
      ${lib.getExe kmodigest} "$module"
    done
  '';

  meta = with lib; {
    description = "MNT Reform Qualcomm Atheros qcacld2 WLAN driver";
    homepage = "https://source.mnt.re/reform/qcacld2";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
