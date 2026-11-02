{
  stdenv,
  lib,
  fetchgit,
  kernel,
  kmodigest,
  qcacld2,
  version ? "3f559de5f4ab26bc66a7fe925b83112fd6ccf9fe",
  hash ? "sha256-uEqZhEftOo0zfQxdrnUfMYMOmMEi32+fS85Id00pqSo=",
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

  buildPhase = ''
    make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" M="$(pwd -P)" modules
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
    cp *.ko $out/lib/modules/${kernel.modDirVersion}/extra/
    runHook postInstall
  '';

  postInstall = ''
    for module in $out/lib/modules/${kernel.modDirVersion}/extra/*.ko; do
      ${lib.getExe kmodigest} "$module" || true
      if [ ! -e "$module.cer" ]; then
        # kmodigest did not create a certificate for this module (it is
        # unsigned); reuse the certificate from the qcacld2 module, which
        # was signed with the same kernel key.
        cp ${qcacld2}/lib/modules/${kernel.modDirVersion}/extra/qcacld2.ko.cer "$module.cer"
      fi
    done
  '';

  meta = with lib; {
    description = "MNT Reform LPC interface driver";
    homepage = "https://source.mnt.re/reform/reform-tools.git";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
