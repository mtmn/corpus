{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    extra-substituters = ["https://attic.saatana.cat/tools"];
    extra-trusted-public-keys = ["tools:jwYUMuvRliZGRiARi2ptFALYDoheCxHI8X4sXWYds/0="];
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        duckdbPrebuilt = pkgs.fetchurl {
          url = "https://npm.duckdb.org/duckdb/duckdb-v1.4.4-node-v137-linux-x64.tar.gz";
          hash = "sha256-Z91EJB81gRaZoLDjkw5lVVQ+jtGIvMV0tMJeOAY7Q3g=";
        };

        # Pinned registry + registry-index so the spago FOD is deterministic
        spagoRegistry = pkgs.fetchFromGitHub {
          owner = "purescript";
          repo = "registry";
          rev = "483aaf573663403afdabe20822ac88d565a65746";
          hash = "sha256-pFVxQzt0+o1+nsCgk+VcprPSmEd8CH3Mkbk0vUy4x3g=";
        };

        spagoRegistryIndex = pkgs.fetchFromGitHub {
          owner = "purescript";
          repo = "registry-index";
          rev = "77163eff5ea12e25d7391cf52fe5b9178145d843";
          hash = "sha256-ez73ecGmzf5d7EkamNZ9KT8u7e4yR7jSvdiGu4bGAHs=";
        };

        # FOD: pre-fetch spago packages (needs network, but is now deterministic)
        spagoDeps = pkgs.stdenv.mkDerivation {
          name = "scorpus-spago-deps";

          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = "sha256-HCj4zn2E+UpeuMsmvvZe8d9nlkn1YF7vZ/j2I2Uoo20=";

          nativeBuildInputs = with pkgs; [nodejs git cacert purescript];

          dontUnpack = true;
          dontFixup = true;

          buildPhase = ''
            export HOME=$TMPDIR
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export NODE_EXTRA_CA_CERTS="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

            # Pre-populate registry so spago doesn't clone from GitHub
            mkdir -p $HOME/.cache/spago-nodejs
            cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
            cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
            chmod -R u+w $HOME/.cache/spago-nodejs

            cp ${self + "/package.json"} package.json
            cp ${self + "/package-lock.json"} package-lock.json
            cp ${self + "/spago.yaml"} spago.yaml
            cp ${self + "/spago.lock"} spago.lock

            npm ci --ignore-scripts
            mkdir -p node_modules/.bin node_modules/purescript/bin
            cp ${pkgs.purescript}/bin/purs node_modules/purescript/bin/purs
            ln -sf ../purescript/bin/purs node_modules/.bin/purs
            patchShebangs node_modules
            npx spago install
          '';

          installPhase = ''
            mkdir -p $out
            cp -r .spago/p $out/packages
          '';
        };

        scorpus = pkgs.buildNpmPackage {
          pname = "scorpus";
          version = "1.0.0";
          src = self;

          npmDepsHash = "sha256-L+9L3RY5CNLudmQL7EZwZO8x0kQ2MKCqSsn37ZIIKWE=";
          npmRebuildFlags = ["--ignore-scripts"];

          nativeBuildInputs = with pkgs; [
            makeWrapper
            nodejs
	    git
            purescript
          ];

          buildPhase = ''
            export HOME="$TMPDIR"

            # Place prebuilt duckdb native addon
            mkdir -p node_modules/duckdb/lib/binding
            tar -xf ${duckdbPrebuilt} -C node_modules/duckdb/lib/binding --strip-components=1

            # Restore spago packages
            mkdir -p .spago
            cp -r ${spagoDeps}/packages .spago/p
            chmod -R u+w .spago

            # Provide pinned registry so spago finds package-sets
            mkdir -p $HOME/.cache/spago-nodejs
            cp -r ${spagoRegistry} $HOME/.cache/spago-nodejs/registry
            cp -r ${spagoRegistryIndex} $HOME/.cache/spago-nodejs/registry-index
            chmod -R u+w $HOME/.cache/spago-nodejs

            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib/scorpus
            cp -r server.js client.js package.json node_modules assets $out/lib/scorpus/
            if [ -f .env ]; then
              cp .env $out/lib/scorpus/
            else
              cp .env.example $out/lib/scorpus/.env
            fi

            mkdir -p $out/bin
            makeWrapper ${pkgs.nodejs}/bin/node $out/bin/scorpus-server \
              --add-flags "--no-deprecation" \
              --add-flags "$out/lib/scorpus/server.js" \
              --chdir "$out/lib/scorpus"
          '';
        };
      in {
        packages.default = scorpus;

        packages.container = pkgs.dockerTools.buildLayeredImage {
          name = "scorpus";
          tag = "latest";
          contents = [pkgs.nodejs pkgs.cacert];
          config = {
            Cmd = ["${scorpus}/bin/scorpus-server"];
            WorkingDir = "/app";
            ExposedPorts = {
              "8321/tcp" = {};
            };
            User = "1000:1000";
            Env = [
              "PORT=8321"
              "NODE_ENV=production"
            ];
          };
          fakeRootCommands = ''
            mkdir -p /app/data
            chown -R 1000:1000 /app
            chmod 700 /app/data
          '';
          enableFakechroot = true;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            purescript
            awscli2
            duckdb
            esbuild
          ];
        };
      }
    );
}
