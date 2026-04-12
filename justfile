help:
    @just --list

# Setup npm and spago
setup:
    npm install
    npx spago install

# Build the project locally
build:
    npm run build

# Run the project locally
run:
    npx spago run

# Run tests
test:
    npm test

# Format PureScript source code
tidy:
    npm run tidy

# Enter the Nix development shell
shell:
    nix develop

# Nix operations (build, run)
nix command:
    @if [ "{{ command }}" = "build" ]; then \
        nix build .; \
    elif [ "{{ command }}" = "run" ]; then \
        ./result/bin/scorpus-server; \
    else \
        echo "Unknown nix command: {{ command }}"; \
        exit 1; \
    fi

# Run quality and security checks
check:
    npx spago build --purs-args "--fail-on-warnings"
    npx purs-tidy check "src/**/*.purs"
    npm audit

# Build the container image using Nix
container:
    nix build .#container

# Load the built container image into podman
load: container
    podman load < result

# Push the container image to the registry
push: container
    skopeo copy --dest-precompute-digests docker-archive:result docker://ghcr.io/mtmn/scorpus:latest
