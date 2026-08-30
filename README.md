# corpus

[![builds.sr.ht status](https://builds.sr.ht/~mtmn/corpus.svg)](https://builds.sr.ht/~mtmn/corpus?)

A self-hosted ListenBrainz and Last.fm listening-history dashboard. Corpus stores scrobbles in DuckDB, enriches release metadata, caches cover art, and serves an Elm web interface.

## Documentation

- [Architecture](docs/architecture.md): components, routes, data flows, configuration and operations
- [DuckDB](docs/duckdb.md): schema and analytical queries

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

Send ListenBrainz-compatible submissions to `POST /1/submit-listens`. Include `Authorization: Token <token>` and a standard ListenBrainz payload. Validate a token with `GET /1/validate-token` and the same header.

Corpus shows tokens once when you create, reset or approve a user. Store them securely.

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

Set `REGISTRATION_ENABLED=true` to allow public registration at `/register`. Set `ADMIN_TOKEN` to enable approval at `/admin`. See the [configuration reference](docs/architecture.md#configuration-reference) for all settings and the registration workflow.
