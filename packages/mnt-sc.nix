{
  stdenv,
  lib,
  fetchgit,
  kernel,
  kmodigest,
  qcacld2 ? null,
  version ? "3f559de5f4ab26bc66a7fe925b83112fd6ccf9fe",
  hash ? "sha256-uEqZhEftOo0zfQxdrnUfMYMOmMEi32+fS85Id00pqSo=",
}:
let
  # Same reform-tools checkout used for the panel driver's sources. The
  # system controller driver moved to `system-controller/` in 2026.
  reform-tools = fetchgit {
    url = "https://source.mnt.re/reform/reform-tools.git";
    rev = "${version}";
    inherit hash;
  };
in
stdenv.mkDerivation {
  pname = "mnt-sc";
  name = "mnt-sc-${version}-${kernel.version}";
  inherit version;

  src = "${reform-tools}/system-controller";

  # Upstream forgot to declare `ret` in show_capacity(); the driver does
  # not build as shipped.
  postPatch = ''
    substituteInPlace mnt-sc.c \
      --replace-fail '	uint16_t cap_acc_mah, cap_min_mah, cap_max_mah;' \
      '	uint16_t cap_acc_mah, cap_min_mah, cap_max_mah;
    	int ret = 0;'
  '';

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
      if ! ${lib.getExe kmodigest} "$module"; then
        ${lib.optionalString (qcacld2 != null) ''
          echo "kmodigest failed for $module; falling back to the qcacld2 certificate" >&2
        ''}
        ${lib.optionalString (qcacld2 == null) ''
          echo "kmodigest failed for $module and qcacld2 is disabled" >&2
          exit 1
        ''}
      fi
      if [ ! -e "$module.cer" ]; then
        ${lib.optionalString (qcacld2 != null) ''
          # kmodigest did not create a certificate for this module (it is
          # unsigned); reuse the certificate from the qcacld2 module, which
          # was signed with the same kernel key.
          cp ${qcacld2}/lib/modules/${kernel.modDirVersion}/extra/qcacld2.ko.cer "$module.cer"
        ''}
        ${lib.optionalString (qcacld2 == null) ''
          echo "kmodigest did not create $module.cer and qcacld2 is disabled" >&2
          exit 1
        ''}
      fi
    done
  '';

  meta = with lib; {
    description = "MNT System Controller driver (s-expression protocol)";
    homepage = "https://source.mnt.re/reform/reform-tools";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
