help:
    @just --list

# Enter the Nix development shell
shell:
    nix develop

# Build the project using Nix
nix-build:
    nix build .

# Build the project locally (using npm)
build:
    npm run build

# Run the project locally
run:
    npm start

# Format PureScript source code
tidy:
    npm run tidy

# Run tests
test:
    npm test

# Build the container image using Nix
container:
    nix build .#container

# Load the built container image into podman
load: container
    podman load < result

# Push the container image to the registry
push: container
    skopeo copy --dest-precompute-digests docker-archive:result docker://ghcr.io/mtmn/scorpus:latest
