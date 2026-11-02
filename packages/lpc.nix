{
  stdenv,
  lib,
  fetchgit,
  kernel,
  version ? "ac415f378b187314c77b328295507d13b49bfdd5",
  hash ? "sha256-4RhRGR7xHdNfLBFOM4GwjCVvar+a///OGN89MRNS0mI=",
}:
let
  reform-tools = fetchgit {
    url = "https://source.mnt.re/reform/reform-tools.git";
    rev = "${version}";
    hash = hash;
  };
in
stdenv.mkDerivation {
  pname = "reform-lpc";
  name = "reform-lpc-${version}-${kernel.version}";
  version = version;

  src = "${reform-tools}/lpc";

  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  postPatch = ''
    # Linux 7.3 replaced power_supply_config.of_node with .fwnode.
    sed -i 's/psy_cfg\.of_node = spi->dev\.of_node;/psy_cfg.fwnode = of_fwnode_handle(spi->dev.of_node);/' \
      reform2_lpc.c
  '';

  buildPhase = ''
    make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" M="$(pwd -P)" modules
  '';

  installPhase = ''
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
    cp *.ko $out/lib/modules/${kernel.modDirVersion}/extra/
  '';

  meta = with lib; {
    description = "MNT Reform LPC interface driver";
    homepage = "https://source.mnt.re/reform/reform-tools.git";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
