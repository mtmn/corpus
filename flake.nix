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
        lib = pkgs.lib;

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
            nodejs
            # Native addon build dependencies
            gnumake
            stdenv.cc
            # DuckDB build dependencies
            duckdb
            # Remove duplicates
          ] ++ lib.optionals stdenv.isLinux [
            # Linux-specific build tools
            glibc
            # Other system dependencies that might be needed
          ];

          buildPhase = ''
            export HOME="$TMPDIR"
            # Node-gyp settings
            export npm_config_nodedir="${pkgs.nodejs}"
            export npm_config_python="${pkgs.python3}/bin/python"
            # C/C++ compiler settings
            export CC="${pkgs.stdenv.cc}/bin/cc"
            export CXX="${pkgs.stdenv.cc}/bin/c++"
            export LINK="${pkgs.stdenv.cc}/bin/cc"
            # Library paths
            export CFLAGS="-I${pkgs.duckdb}/include"
            export LDFLAGS="-L${pkgs.duckdb}/lib"
            # Enable multi-core building
            export npm_config_jobs="$NIX_BUILD_CORES"
            
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib/scorpus
            cp -r server.js client.js package.json node_modules assets $out/lib/scorpus/

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
            esbuild
            # Native addon build dependencies
            gnumake
            stdenv.cc
            python3
            pkg-config
          ];
        };
      }
    );
}
