{
  stdenv,
  lib,
  kernel,
  kmodigest,
}:
stdenv.mkDerivation {
  pname = "panel-mnt-pocket-reform";
  version = kernel.version;

  src = ./panel-mnt-pocket-reform/src;
  nativeBuildInputs = kernel.moduleBuildDependencies;

  postPatch = ''
    # On the Pocket Reform the panel reset / DCDC enable lines are driven by
    # the system controller, not by Linux GPIOs. Make them optional so the
    # driver does not log -ENOENT at every boot.
    sed -i \
      -e 's/devm_gpiod_get(dev, "reset"/devm_gpiod_get_optional(dev, "reset"/' \
      -e 's/devm_gpiod_get(dev, "dcdc-en"/devm_gpiod_get_optional(dev, "dcdc-en"/' \
      -e 's/!IS_ERR(jdi->reset_gpio)/!IS_ERR_OR_NULL(jdi->reset_gpio)/g' \
      -e 's/!IS_ERR(jdi->dcdc_en_gpio)/!IS_ERR_OR_NULL(jdi->dcdc_en_gpio)/g' \
      *.c
  '';

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
