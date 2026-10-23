set lazy

# Tagged with the Nix store hash, so every distinct image gets its own tag
fly_tag := `git describe --tags --always` + "-" + `basename "$(nix eval --raw .#container.outPath)" | cut -c1-8`
fly_image := "registry.fly.io/" + env("FLY_APP") + ":" + fly_tag

help:
    @just --list

# Bump version, update CHANGELOG, tag, and push (requires git-cliff)
bump:
    @hack/git-release


# Setup pnpm and spago
setup:
    pnpm install
    pnpm spago install

# Build the project locally
build:
    pnpm run build

# Build a release
release:
    pnpm run release

# Run the project locally
run:
    pnpm spago run

# Build and run locally
dev: build run

# Run tests
test:
    pnpm test

# Format PureScript source code
tidy:
    pnpm run tidy

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

# Render docs diagrams (requires graphviz)
docs:
    hack/graphviz docs/architecture.dot

# Run quality and security checks
check:
    pnpm spago build --strict
    pnpm exec purs-tidy check "src/**/*.purs" "test/**/*.purs"
    pnpm exec elm make src/Client.elm --output=/tmp/corpus-client.js
    pnpm exec elm-test

# Manage the container image (build, load, push)
oci command:
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

# Build the container image and push it to the Fly.io registry
fly-push: (oci "build")
    flyctl auth docker
    skopeo copy --dest-precompute-digests docker-archive:result docker://{{ fly_image }}

# Deploy the container image for the current source to Fly.io
fly-deploy:
    flyctl deploy --ha=false --image {{ fly_image }}

# Push and deploy to Fly.io
fly: fly-push fly-deploy
