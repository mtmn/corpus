help:
    @just --list


# Setup npm and spago
setup: generate-users-json
    npm install
    npx spago install

# Build the project locally
build: generate-users-json
    npm run build

# Build a release
release: generate-users-json
    npm run release

# Run the project locally
run:
    npx spago run

# Build and run locally
dev: build run

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

# Add a new user (--slug and --db required; --name, --listenbrainz-user, --lastfm-user optional)
add-user *args:
    node server.js add-user {{args}}

# Reset the API token for a user (--slug required)
reset-token *args:
    node server.js reset-token {{args}}

# List all users
list-users:
    node server.js list-users

# Run quality and security checks
check:
    npx whine
    npx spago build --strict
    npx purs-tidy check "src/**/*.purs"
    elm-analyse
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
