{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libplacebo";
  packageLock = (import ../../../packages.lock.nix).${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith { inherit pkgs os arch; };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };
  python = pkgs.python3.withPackages (pythonPkgs: [
    pythonPkgs.jinja2
    pythonPkgs.markupsafe
    pythonPkgs.glad2
  ]);

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  patchedSource = pkgs.runCommand "${pname}-patched-source-${version}" { } ''
    cp -r ${src} src
    export src=$PWD/src
    chmod -R 777 $src

    # GitHub archives do not include libplacebo's submodules. Keep the build
    # self-contained by filling the two header-only submodules needed even when
    # GPU backends are disabled.
    mkdir -p $src/3rdparty/Vulkan-Headers
    cp -R ${pkgs.vulkan-headers}/include $src/3rdparty/Vulkan-Headers/
    mkdir -p $src/3rdparty/Vulkan-Headers/registry
    cp ${pkgs.vulkan-headers}/share/vulkan/registry/vk.xml \
      $src/3rdparty/Vulkan-Headers/registry/

    mkdir -p $src/3rdparty/fast_float
    cp -R ${pkgs."fast-float"}/include $src/3rdparty/fast_float/

    substituteInPlace $src/meson.build \
      --replace "python_env.append('PYTHONPATH', thirdparty/'glad')" \
                "python_env.append('PYTHONPATH', thirdparty/'glad')
    python_env.append('PYTHONPATH', '${python}/${pkgs.python3.sitePackages}')"

    cp -r $src $out
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${version}";
  pname = pname;
  inherit version;
  src = patchedSource;
  dontUnpack = true;
  enableParallelBuilding = true;
  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    python
  ];
  configurePhase = ''
    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Ddefault_library=shared \
      -Dvulkan=disabled \
      -Dvk-proc-addr=disabled \
      -Dopengl=enabled \
      -Dgl-proc-addr=enabled \
      -Dd3d11=disabled \
      -Dglslang=disabled \
      -Dshaderc=disabled \
      -Dlcms=disabled \
      -Ddovi=disabled \
      -Dlibdovi=disabled \
      -Ddemos=false \
      -Dtests=false \
      -Dbench=false \
      -Dfuzz=false \
      -Dunwind=disabled \
      -Dxxhash=disabled
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build
  '';
}
