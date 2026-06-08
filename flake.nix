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
      url = "https://registry.npmjs.org/@duckdb/node-bindings-linux-x64/-/node-bindings-linux-x64-1.5.2-r.1.tgz";
      hash = "sha256-IMn1URw5Cn5hN801LmHoI/XgGrezlkcF+5ItJNeclvg=";
    };

    spagoRegistry = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry";
      rev = "7c020ee4076070dfc917ed0efa6129ce1b60c0a8";
      hash = "sha256-5fxgKomfEI0SqLC/b55H5mLitLbXGh1syEWzuupwK7Y=";
    };

    spagoRegistryIndex = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry-index";
      rev = "0f05445d856c828ef029fd9a982e119038778eda";
      hash = "sha256-cwp/L0YgKtbwyL0JhUsR8VTubmGxoaYgjHEwmI4Cypo=";
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
      hash = "sha256-H8XTwSL9ura4VYTrBQwqtxt881TDBXOZyoUzAHDvep4=";
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

      nativeBuildInputs = with pkgs; [nodejs_24 git cacert purescript pnpm];

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
        ln -sf ${pkgs.purescript}/bin/purs node_modules/.bin/purs
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
        nodejs_24
        git
        purescript
        elmPackages.elm
        pnpm
        pnpmConfigHook
      ];

      buildPhase = ''
        mkdir -p node_modules/@duckdb/node-bindings-linux-x64
        tar -xf ${duckdbPrebuilt} -C node_modules/@duckdb/node-bindings-linux-x64 --strip-components=1

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
        makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/corpus-server \
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
        pkgs.nodejs_24
        pkgs.purescript
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
