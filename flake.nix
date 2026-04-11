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
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};

        scorpus = pkgs.buildNpmPackage {
          pname = "scorpus";
          version = "1.0.0";
          src = self;

          npmDepsHash = "sha256-L+9L3RY5CNLudmQL7EZwZO8x0kQ2MKCqSsn37ZIIKWE=";

          nativeBuildInputs = with pkgs; [
            purescript
            spago
            esbuild
            makeWrapper
            python3
            pkg-config
            gcc
            gnumake
          ];

          npmFlags = ["--build-from-source"];

          buildPhase = ''
            export HOME=$TMPDIR
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib/scorpus
            cp -r server.js client.js package.json node_modules $out/lib/scorpus/

            mkdir -p $out/bin
            makeWrapper ${pkgs.nodejs}/bin/node $out/bin/scorpus-server \
              --add-flags "--no-deprecation" \
              --add-flags "$out/lib/scorpus/server.js"
          '';
        };
      in {
        packages.default = scorpus;

        packages.oci = pkgs.dockerTools.buildLayeredImage {
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
              "DATABASE_FILE=/app/data/scorpus.db"
              "NODE_ENV=production"
            ];
          };
          extraCommands = ''
            mkdir -p app/data
            chown -R 1000:1000 app
            chmod 700 app/data
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            purescript
            awscli2
            duckdb
            spago
            purs-tidy
            esbuild
          ];
        };
      }
    );
}
