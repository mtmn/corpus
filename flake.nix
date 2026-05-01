{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    elm2nix.url = "github:dwayne/elm2nix";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    elm2nix,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        inherit
          (elm2nix.lib.elm2nix pkgs)
          generateRegistryDat
          prepareElmHomeScript
          ;

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

          npmDepsHash = "sha256-mWtapB6mIfm7+ZQC4YiZUj2zBqKpiKvPMnuI8AE9hE0=";
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

            mkdir -p node_modules/duckdb/lib/binding
            tar -xf ${duckdbPrebuilt} -C node_modules/duckdb/lib/binding --strip-components=1

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
        devShells.default = pkgs.mkShell {
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

        packages.default = corpus;
      }
    );
}
