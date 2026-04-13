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
        ./result/bin/corpus-server; \
    else \
        echo "Unknown nix command: {{ command }}"; \
        exit 1; \
    fi

# Run quality and security checks
check:
    npx spago build --strict
    npx purs-tidy check "src/**/*.purs"
    statix check .

# Manage the container image (build, load, push)
container command:
    @if [ "{{ command }}" = "build" ]; then \
        nix build .#container; \
    elif [ "{{ command }}" = "load" ]; then \
        podman load < result; \
    elif [ "{{ command }}" = "push" ]; then \
        skopeo copy \
            --dest-precompute-digests \
            docker-archive:result docker://ghcr.io/mtmn/corpus:latest; \
    else \
        echo "Unknown container command: {{ command }}"; \
        exit 1; \
    fi
