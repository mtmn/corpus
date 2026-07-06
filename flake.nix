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

    inherit
      (elm2nix.lib.elm2nix pkgs)
      generateRegistryDat
      prepareElmHomeScript
      ;

    duckdbPrebuilt = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@duckdb/node-bindings-linux-x64/-/node-bindings-linux-x64-1.5.4-r.1.tgz";
      sha256 = "056c0ea133e54e1c74b21a09f1cf3fe1f6c497644e2c7dd6ecac4ae612fa0b5c";
    };

    spagoRegistry = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry";
      rev = "9ec4b408f38d1b61069922991c86ce63a0a30022";
      hash = "sha256-pmfd6F7x8ZSEwwzJR2pzT5cvK5S1YNdZW31WhpiyfPw=";
    };

    spagoRegistryIndex = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry-index";
      rev = "c7ad501685bfbbeb1192ff3d2f19e23a2cf0e48b";
      hash = "sha256-J5SUrDrRNIRRHwyQ/k7oZi+oBXmtvcBUGs/Auf1YdzY=";
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
      hash = "sha256-/cUYadYeNoFyStuEE4Ztc5jToY4BsJ2/a+CMh35OmWA=";
      fetcherVersion = 3;
    };

    spagoDeps = pkgs.stdenv.mkDerivation {
      name = "corpus-spago-deps";
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = "sha256-sdor+SLxjw/e+OQeBiEyKyWeBLVaGo2tcAxf06vxth8=";

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
        elmPackages.elm
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
      contents = [corpus];
      extraCommands = "mkdir -p tmp";
      config.Cmd = ["${corpus}/bin/corpus-server"];
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "corpus";
      packages = [
        elm2nix.packages.${system}.default
        pkgs.nodejs
        pkgs.elmPackages.elm
        pkgs.elmPackages.elm-format
        pkgs.elmPackages.elm-json
        pkgs.pnpm
      ];
    };

    packages.${system} = {
      default = corpus;
      container = dockerImage;
    };
  };
}
