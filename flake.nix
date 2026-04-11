{
  description = "ListenBrainz frontend in PureScript";

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
          ];

          buildPhase = ''
            export HOME=$TMPDIR
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib
            cp server.js client.js package.json $out/lib/
            mkdir -p $out/bin
            echo "#!/bin/sh" > $out/bin/scorpus-server
            echo "${pkgs.nodejs}/bin/node --no-deprecation $out/lib/server.js" >> $out/bin/scorpus-server
            chmod +x $out/bin/scorpus-server
          '';
        };
      in {
        packages.default = scorpus;

        packages.oci = pkgs.dockerTools.buildLayeredImage {
          name = "scorpus";
          tag = "latest";
          contents = [pkgs.nodejs pkgs.cacert];
          config = {
            Cmd = ["${pkgs.nodejs}/bin/node" "--no-deprecation" "/app/server.js"];
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
            cp ${scorpus}/lib/server.js app/
            cp ${scorpus}/lib/client.js app/

            chown -R 1000:1000 app
            chmod 700 app/data
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            purescript
            spago
            purs-tidy
            esbuild
          ];
        };
      }
    );
}
