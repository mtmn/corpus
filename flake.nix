{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    elm2nix.url = "github:mtmn/elm2nix";
  };

  outputs = {
    self,
    nixpkgs,
    elm2nix,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    elm2nixLib = pkgs.callPackage (elm2nix + "/nix") {
      elmVersion = "0.19.2";
    };

    inherit
      (elm2nixLib)
      generateRegistryDat
      prepareElmHomeScript
      ;

    duckdbPrebuilt = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@duckdb/node-bindings-linux-x64/-/node-bindings-linux-x64-1.5.4-r.1.tgz";
      sha256 = "056c0ea133e54e1c74b21a09f1cf3fe1f6c497644e2c7dd6ecac4ae612fa0b5c";
    };

    elm = pkgs.stdenvNoCC.mkDerivation {
      pname = "elm";
      version = "0.19.2";
      src = pkgs.fetchurl {
        url = "https://github.com/elm/compiler/releases/download/0.19.2/elm-0.19.2-linux-x64.gz";
        hash = "sha256-ZjINJ3AWVPoRvQ6NhL35gpaU1XcMjc7i3t5hYPrVhzc=";
      };
      dontUnpack = true;
      nativeBuildInputs = [pkgs.gzip];
      buildPhase = "gzip -dc $src > elm";
      installPhase = "install -Dm755 elm $out/bin/elm";
    };

    spagoRegistry = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry";
      rev = "07e5d19c16aacc016dc9419cd791bab4b30b6b2e";
      hash = "sha256-qAjmHhjUqDSWh+wrbXdP45OBGlfP9ZXXLT8P9HQlQEo=";
    };

    spagoRegistryIndex = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry-index";
      rev = "1314ac1ed481d2b408dac72be00ca6c3ddd8571c";
      hash = "sha256-66bIEsWROF7VEtKUtYjWxlPK3umCgqFAmocgzGkW8HA=";
    };

    registryDat = generateRegistryDat {elmLock = ./elm.lock;};

    elmHomeScript = prepareElmHomeScript {
      elmLock = ./elm.lock;
      inherit registryDat;
    };

    pnpmDeps = pkgs.fetchPnpmDeps {
      src = pkgs.lib.cleanSourceWith {
        src = self;
        filter = name: _type: let
          baseName = baseNameOf (toString name);
        in
          pkgs.lib.elem baseName [
            "package.json"
            "pnpm-lock.yaml"
            "pnpm-workspace.yaml"
          ];
        name = "corpus-pnpm-source";
      };
      pname = "corpus";
      hash = "sha256-3dF7TJo2Bm52QUekTN6VObfZF1t3o70sH3nkIt5Kbmw=";
      fetcherVersion = 4;
    };

    spagoDeps = pkgs.stdenv.mkDerivation {
      name = "corpus-spago-deps";
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = "sha256-Roj/G7HhLjA6PKNBt7YA9LIxP0jLc6BdnIpKDgSJvPo=";

      src = pkgs.lib.cleanSourceWith {
        src = self;
        filter = name: _type: let
          baseName = baseNameOf (toString name);
        in
          pkgs.lib.elem baseName [
            "package.json"
            "pnpm-lock.yaml"
            "pnpm-workspace.yaml"
            "spago.yaml"
            "spago.lock"
          ];
      };

      nativeBuildInputs = with pkgs; [nodejs git cacert pnpm];

      buildPhase = ''
        export HOME=$TMPDIR
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

        mkdir -p $HOME/.cache/spago-nodejs
        cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
        cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
        chmod -R u+w $HOME/.cache/spago-nodejs

        pnpm install --frozen-lockfile
        patchShebangs node_modules
        mkdir -p node_modules/.bin
        pnpm spago install
      '';

      installPhase = ''
        mkdir -p $out
        cp -r .spago/p $out/packages
      '';
    };

    src = pkgs.lib.cleanSourceWith {
      src = self;
      filter = name: _type: let
        relPath =
          pkgs.lib.removePrefix (toString self + "/") (toString name);
        topDir = builtins.head (pkgs.lib.splitString "/" relPath);
      in
        pkgs.lib.elem topDir [
          "package.json"
          "pnpm-lock.yaml"
          "pnpm-workspace.yaml"
          "elm.json"
          "spago.yaml"
          "spago.lock"
          "server.js"
          "client.js"
          "assets"
          "users.json"
          "src"
        ];
    };

    corpus = pkgs.stdenv.mkDerivation {
      pname = "corpus";
      inherit (builtins.fromJSON (builtins.readFile ./package.json)) version;
      inherit src;

      inherit pnpmDeps;

      nativeBuildInputs = with pkgs; [
        makeWrapper
        nodejs
        git
        elm
        purescript
        pnpm
        pnpmConfigHook
      ];

      buildPhase = ''
        mkdir -p node_modules/@duckdb/node-bindings-linux-x64
        tar -xf ${duckdbPrebuilt} -C node_modules/@duckdb/node-bindings-linux-x64 --strip-components=1

        ln -sf ${pkgs.purescript}/bin/purs node_modules/.bin/purs

        mkdir -p .spago
        cp -r ${spagoDeps}/packages .spago/p
        chmod -R u+w .spago

        mkdir -p $HOME/.cache/spago-nodejs
        cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
        cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
        chmod -R u+w $HOME/.cache/spago-nodejs

        eval ${elmHomeScript}
        pnpm run release
      '';

      installPhase = ''
        mkdir -p $out/lib/corpus
        cp -r server.js client.js users.json package.json node_modules assets $out/lib/corpus/
        mkdir -p $out/bin
        makeWrapper ${pkgs.nodejs}/bin/node $out/bin/corpus-server \
          --add-flags "--no-deprecation" \
          --add-flags "$out/lib/corpus/server.js" \
          --chdir "$out/lib/corpus"
      '';
    };
    dockerImage = pkgs.dockerTools.buildLayeredImage {
      name = "corpus";
      tag = corpus.version;
      contents = [corpus pkgs.cacert pkgs.dockerTools.fakeNss];
      extraCommands = "mkdir -p tmp";
      config = {
        Cmd = ["${corpus}/bin/corpus-server"];
        Env = ["SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
      };
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "corpus";
      packages = [
        elm2nix.packages.${system}.default
        pkgs.nodejs
        elm
        pkgs.elmPackages.elm-format
        pkgs.elmPackages.elm-json
        pkgs.pnpm
        pkgs.statix
        pkgs.git-cliff
        pkgs.flyctl
        pkgs.skopeo
      ];
    };

    packages.${system} = {
      default = corpus;
      container = dockerImage;
    };
  };
}
