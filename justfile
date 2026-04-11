help:
    @just --list

shell:
    nix develop

build:
    nix build .

container:
    nix build .#container

load: container
    podman load < result

push: container
    skopeo copy --dest-precompute-digests docker-archive:result docker://ghcr.io/mtmn/scorpus:latest
