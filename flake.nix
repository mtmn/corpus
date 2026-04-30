{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      duckdbPrebuilt = pkgs.fetchurl {
        url = "https://npm.duckdb.org/duckdb/duckdb-v1.4.4-node-v137-linux-x64.tar.gz";
        hash = "sha256-Z91EJB81gRaZoLDjkw5lVVQ+jtGIvMV0tMJeOAY7Q3g=";
      };

      spagoRegistry = pkgs.fetchFromGitHub {
        owner = "purescript";
        repo = "registry";
        rev = "19f237b9f13c7b286ce2e7129d25d575db787bee";
        hash = "sha256-xC8+jSfKM/MmdmAqRQ44ccRFTAvpwAnnAVs4IRoDhL4=";
      };

      spagoRegistryIndex = pkgs.fetchFromGitHub {
        owner = "purescript";
        repo = "registry-index";
        rev = "77163eff5ea12e25d7391cf52fe5b9178145d843";
        hash = "sha256-ez73ecGmzf5d7EkamNZ9KT8u7e4yR7jSvdiGu4bGAHs=";
      };

      elmRegistry = pkgs.fetchFromGitHub {
        owner = "elm";
        repo = "package.elm-lang.org";
        rev = "afe1a128b4bbf5ec0ebc21886d32b0b473794a9e";
        hash = "sha256-aaflueHul/lXA/v8YM5Irckl8+jEUMsvkSS5nh9eYCg=";
      };

      elmDeps = pkgs.stdenv.mkDerivation {
        name = "corpus-elm-deps";

        src = pkgs.lib.cleanSourceWith {
          src = self;
          filter = name: _type: let
            baseName = baseNameOf (toString name);
          in
            pkgs.lib.elem baseName
            [
              "elm.json"
              "src"
              "Client.elm"
              "Api.elm"
              "State.elm"
              "Types.elm"
              "View.elm"
            ];
        };

        nativeBuildInputs = with pkgs; [elmPackages.elm cacert];

        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = "sha256-3D0PJQH1AkHdt7eGmbplZBX1FXmS2hb36enYU7ajqY4=";

        buildPhase = ''
          export HOME=$TMPDIR
          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export ELM_HOME=$HOME/.elm

          # Populate the Elm package registry from the fetched snapshot.
          mkdir -p $ELM_HOME/0.19.1/registry
          cp -r ${elmRegistry}/* $ELM_HOME/0.19.1/registry/

          elm make src/Client.elm --output=/dev/null
        '';

        installPhase = ''
          mkdir -p $out
          cp -r $HOME/.elm/0.19.1/packages $out/
        '';
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

          # Pre‑populate registry so spago doesn't clone from GitHub
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
        filter = name: type: let
          baseName = baseNameOf (toString name);
        in
          !((type == "directory" && (baseName == "docs" || baseName == ".git"))
            || (type
              == "regular"
              && (
                pkgs.lib.hasSuffix ".md" baseName
                || baseName == "justfile"
                || baseName == "flake.nix"
                || baseName == "flake.lock"
              )));
      };

      corpus = pkgs.buildNpmPackage {
        pname = "corpus";
        inherit ((builtins.fromJSON (builtins.readFile ./package.json))) version;
        inherit src;

        npmDepsHash = "sha256-uwag7hUAc4zKsXNAyPIfvl7ReTQm8H5s0y1UOhDjZDg=";
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

          # DuckDB bindings
          mkdir -p node_modules/duckdb/lib/binding
          tar -xf ${duckdbPrebuilt} -C node_modules/duckdb/lib/binding --strip-components=1

          # Spago packages
          mkdir -p .spago
          cp -r ${spagoDeps}/packages .spago/p
          chmod -R u+w .spago

          # Spago registry cache
          mkdir -p $HOME/.cache/spago-nodejs
          cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
          cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
          chmod -R u+w $HOME/.cache/spago-nodejs

          # Elm packages
          mkdir -p $HOME/.elm/0.19.1
          cp -r ${elmDeps}/packages $HOME/.elm/0.19.1/
          chmod -R u+w $HOME/.elm

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
      packages = {
        default = corpus;
        inherit elmDeps spagoDeps;
      };
    });
}
