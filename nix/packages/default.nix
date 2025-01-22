{ cacert
, cargo
, fetchFromGitHub
, gcc
, gnumake
, jq
, lib
, napi-rs-cli
, node-gyp
, nodejs_20
, openssl
, prisma-engines
, python3
, rustPlatform
, rustc
, stdenv
, stdenvNoCC
, yarn-berry
, writeShellScript
}:
let
  nodejs = nodejs_20;
  yarn = yarn-berry.override { inherit nodejs; };
  affine-start-script = writeShellScript "affine-server" ''
    dir=$(dirname $0)
    cd $dir/../lib

    # ${nodejs}/bin/node --import ./scripts/register.js ./dist/index.js
    ${nodejs}/bin/node ./scripts/self-host-predeploy.js \
        && ${nodejs}/bin/node ./dist/index.js
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "affine-server";
  version = "0.19.6";
  GITHUB_SHA = "c5da8ddb1ee7b71377cd822957e8e0e9d03c397f";
  BUILD_TYPE = "stable";

  src = fetchFromGitHub {
    owner = "toeverything";
    repo = "AFFiNE";
    rev = "v${finalAttrs.version}";
    hash = "sha256-BydTNE36oRIxr2lTnc2+EY0lvMXn4NTLB4EjqzhdjGk=";
  };

  patches = [ ./config-dir.patch ];

  nativeBuildInputs = [
    cargo
    gnumake
    gcc
    openssl
    prisma-engines
    jq
    napi-rs-cli
    nodejs
    node-gyp
    python3
    rustPlatform.cargoSetupHook
    rustc
    yarn
  ];

  # https://github.com/NixOS/nixpkgs/issues/254369#issuecomment-2080460150
  yarnOfflineCache = stdenvNoCC.mkDerivation {
    name = "yarn-offline-cache";
    src = finalAttrs.src;

    nativeBuildInputs = [
      yarn
      prisma-engines
      cacert
    ];

    supportedArchitectures = builtins.toJSON {
      os = [ "linux" ];
      cpu = [ "arm" "arm64" "x64" ];
      libc = [ "glibc" ];
    };

    buildPhase = ''
      export HOME="$NIX_BUILD_TOP"
      export CI=1

      mkdir -p $out
      yarn config set enableTelemetry false
      yarn config set cacheFolder $out
      yarn config set enableGlobalCache false
      yarn config set supportedArchitectures --json "$supportedArchitectures"

      yarn install --immutable --mode=skip-build
    '';

    dontInstall = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-FFO6SwDt5dPNwQpmBCoMJM4Cn9lEgKwJ8QqXrAIc3A8=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    src = finalAttrs.src;
    hash = "sha256-racjpf0VgNod6OxWKSaCbKS9fEkInpDyhVbAHfYWIDo=";
  };

  # TODO: run the version script
  # https://github.com/toeverything/AFFiNE/blob/canary/.github/actions/setup-version/action.yml
  configurePhase = ''
    runHook preConfigure

    export HOME="$NIX_BUILD_TOP"
    export CI=1

    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    export PRISMA_QUERY_ENGINE_BINARY=${prisma-engines}/bin/query-engine
    export PRISMA_QUERY_ENGINE_LIBRARY=${prisma-engines}/lib/libquery_engine.node
    export PRISMA_SCHEMA_ENGINE_BINARY=${prisma-engines}/bin/schema-engine
    export npm_config_nodedir=${nodejs}

    yarn config set enableTelemetry false
    yarn config set enableGlobalCache false
    yarn config set cacheFolder $yarnOfflineCache

    patchShebangs ./scripts/set-version.sh
    ./scripts/set-version.sh ${finalAttrs.version}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    yarn config set nmMode classic
    # yarn config set nmHoistingLimits workspaces

    yarn workspaces focus \
        @affine-tools/cli \
        @affine/admin \
        @affine/mobile \
        @affine/monorepo \
        @affine/server \
        @affine/server-native \
        @affine/web

    yarn affine @affine/admin build
    yarn affine @affine/mobile build
    yarn affine @affine/web build
    yarn workspace @affine/server build
    yarn workspace @affine/server-native build

    yarn workspace @affine/server prisma generate

    find . -name 'node_modules' -type d -prune -exec rm -rf '{}' +
    yarn workspaces focus @affine/server --production

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    cp -r packages/backend/server $out/lib
    cp packages/backend/native/server-native.node $out/lib/
    cp -r packages/frontend/apps/web/dist $out/lib/static
    cp -r packages/frontend/apps/mobile/dist $out/lib/static/mobile
    cp -r packages/frontend/admin/dist $out/lib/static/admin

    # ln -s $out/lib/node_modules/.bin/affine $out/bin/affine
    cp ${affine-start-script} $out/bin/affine-server

    runHook postInstall
  '';

  fixupPhase = ''
    runHook preFixup

    patchShebangs $out/lib

    runHook postFixup
  '';

  meta = {
    description = "A privacy-focused, local-first, open-source, and ready-to-use alternative for Notion & Miro.";
    homepage = "https://affine.pro";
    license = lib.licenses.mit;
  };
})
