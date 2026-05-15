{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    elm2nix.url = "github:dwayne/elm2nix";
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
      rev = "41f6122ddf9b40b7b989c55b53d7305836f81024";
      hash = "sha256-Umk8zXYOfvsL7GVnSfNRpFzUUjCa/VatM4JeS9tjFIY=";
    };

    spagoRegistryIndex = pkgs.fetchFromGitHub {
      owner = "purescript";
      repo = "registry-index";
      rev = "4fa6b28e4af93d0e6693606c412b45d334d99f73";
      hash = "sha256-zEyC6BnI9mtWdwvRaNkJTTRzjDpXwoUn7piSPpXGcPU=";
    };

    registryDat = generateRegistryDat {elmLock = ./elm.lock;};

    elmHomeScript = prepareElmHomeScript {
      elmLock = ./elm.lock;
      inherit registryDat;
    };

    spagoDeps = pkgs.stdenv.mkDerivation {
      name = "corpus-spago-deps";

      src = pkgs.lib.cleanSourceWith {
        src = self;
        filter = name: _type: let
          baseName = baseNameOf (toString name);
        in
          pkgs.lib.elem baseName
          [
            "package.json"
            "package-lock.json"
            "spago.yaml"
            "spago.lock"
          ];
      };

      nativeBuildInputs = with pkgs; [nodejs git cacert purescript];

      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = "sha256-dBorhgF/CIngAe+6fvvGHnGkQsk070SDZbgF5xTGx9c=";

      buildPhase = ''
        export HOME=$TMPDIR
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

        mkdir -p $HOME/.cache/spago-nodejs
        cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
        cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
        chmod -R u+w $HOME/.cache/spago-nodejs

        npm ci --ignore-scripts
        patchShebangs node_modules
        mkdir -p node_modules/.bin
        ln -sf ${pkgs.purescript}/bin/purs node_modules/.bin/purs
        npx spago install
      '';

      installPhase = ''
        mkdir -p $out
        cp -r .spago/p $out/packages
      '';
    };

    src = pkgs.lib.cleanSourceWith {
      src = self;
      filter = name: _type: let
        relPath = pkgs.lib.removePrefix (toString self + "/") (toString name);
        topDir = builtins.head (pkgs.lib.splitString "/" relPath);
      in
        pkgs.lib.elem topDir [
          ".env.example"
          "package.json"
          "package-lock.json"
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

    corpus = pkgs.buildNpmPackage {
      pname = "corpus";
      inherit ((builtins.fromJSON (builtins.readFile ./package.json))) version;
      inherit src;

      npmDepsHash = "sha256-jZKbs5cdydkBhRdWqro4nc4IPZ100hq8aNs7H3qHhgc=";
      npmRebuildFlags = ["--ignore-scripts"];

      nativeBuildInputs = with pkgs; [
        makeWrapper
        nodejs
        git
        purescript
        elmPackages.elm
      ];

      buildPhase = ''
        export HOME="$TMPDIR"

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
        npm run release
      '';

      installPhase = ''
        mkdir -p $out/lib/corpus
        cp -r server.js client.js users.json package.json node_modules assets $out/lib/corpus/
        if [ -f .env ]; then
          cp .env $out/lib/corpus/
        else
          cp .env.example $out/lib/corpus/.env
        fi

        mkdir -p $out/bin
        makeWrapper ${pkgs.nodejs}/bin/node $out/bin/corpus-server \
          --add-flags "--no-deprecation" \
          --add-flags "$out/lib/corpus/server.js" \
          --chdir "$out/lib/corpus"
      '';
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "corpus";
      packages = [
        elm2nix.packages.${system}.default
        pkgs.nodejs
        pkgs.purescript
        pkgs.elmPackages.elm
        pkgs.elmPackages.elm-format
        pkgs.elmPackages.elm-json
      ];
    };

    packages.${system}.default = corpus;
  };
}
