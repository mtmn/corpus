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
      in {
        packages.default = pkgs.buildNpmPackage {
          pname = "scorpus";
          version = "1.0.0";
          src = pkgs.lib.cleanSource ./.;

          npmDepsHash = "sha256-L+9L3RY5CNLudmQL7EZwZO8x0kQ2MKCqSsn37ZIIKWE=";

          nativeBuildInputs = with pkgs; [ purescript spago esbuild makeWrapper ];

          # npm install will try to download purescript/spago binaries by default.
          # We want to use the ones from nixpkgs.
          PURESCRIPT_DOWNLOAD_BINARY = "0";
          SPAGO_DOWNLOAD_BINARY = "0";

          # We need to run spago build and then esbuild.
          # buildNpmPackage's buildPhase runs 'npm run build' by default.
          # We can override it if we want.
          buildPhase = ''
            export HOME=$TMPDIR
            # Since we are using pkgs.spago, we might need to tell it where to find packages.
            # But it will still try to download them if they are not there.
            # For now, let's see what happens.
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/lib/scorpus
            cp server.js client.js package.json $out/lib/scorpus/
            cp -r node_modules $out/lib/scorpus/

            mkdir -p $out/bin
            makeWrapper ${pkgs.nodejs}/bin/node $out/bin/scorpus-server \
              --add-flags "--no-deprecation" \
              --add-flags "$out/lib/scorpus/server.js"
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ nodejs esbuild purs-tidy ];
        };
      }
    );
}
