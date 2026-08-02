# corpus

[![builds.sr.ht status](https://builds.sr.ht/~mtmn/corpus.svg)](https://builds.sr.ht/~mtmn/corpus?)

A self-hosted ListenBrainz and Last.fm listening-history dashboard. Corpus stores scrobbles in DuckDB, enriches release metadata, caches cover art, and serves an Elm web interface.

## Documentation

- [Architecture](docs/architecture.md) — components, routing, data flows, configuration, and operations.
- [DuckDB](docs/duckdb.md) — schema and analytical queries.

## Quick start

With Nix:

```sh
just shell
just nix build
just nix run
```

Or build locally with pnpm:

```sh
pnpm install
pnpm spago install
pnpm run build
pnpm test
pnpm spago run
```

## Scrobbling API

Corpus accepts ListenBrainz-compatible submissions at `POST /1/submit-listens`. Send `Authorization: Token <token>` and a standard ListenBrainz payload. Clients may first validate a token with `GET /1/validate-token` using the same header.

Tokens are shown once when a user is created, reset, or approved through self-registration. Store them securely.

## Configuration

`users.json` defines each static user's slug, source usernames, DuckDB filename, and cover/backup settings. Shared secrets and integrations are supplied by environment variables.

| Variable | Purpose |
|---|---|
| `CORPUS_USERS_FILE` | Static user configuration (default: `users.json`) |
| `DATABASE_PATH` | Directory containing user databases |
| `LASTFM_API_KEY`, `DISCOGS_TOKEN` | Last.fm sync and metadata/cover fallbacks |
| `S3_BUCKET` and `AWS_*` | Cover cache and optional database backups |
| `COSINE_API_KEY` | Similar-track lookup |
| `PORT`, `HOST` | HTTP listener (defaults: `8000`, `127.0.0.1`) |
| `METRICS_ENABLED` | Enable Prometheus metrics at `/metrics` |

Set `REGISTRATION_ENABLED=true` to allow public registration at `/register`; `ADMIN_TOKEN` enables approval at `/admin`. See the [architecture guide](docs/architecture.md#configuration-reference) for every setting and the full registration workflow.
