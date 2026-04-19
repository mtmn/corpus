# corpus
A self-hosted [ListenBrainz](https://listenbrainz.org) and [Last.fm](https://last.fm) frontend that stores metadata and cover images.

It includes storing scrobbles, metadata enrichment, and an interactive [PureScript](https://purescript.org) frontend for exploration of your listening habits.

[Example instance](https://scrobbler.mtmn.name)

## Documentation

- [Architecture](docs/architecture.md) — Deep dive into the system components, data flow, and FFI usage.
- [DuckDB](docs/duckdb.md) — Schema details, analytical queries, and tools for data exploration.

## Usage

This project uses [just](https://github.com/casey/just) and [Nix](https://nixos.org) for development and deployment.

### Development

```bash
# Enter the development shell (includes PureScript, DuckDB, etc.)
just shell

# Build
just nix build

# Run the binary built by Nix
just nix run
```

### Build

```bash
# Install dependencies
npx spago install

# Build the project
npx spago build

# Run tests
npx spago test

# Bundle the client for the browser
npx spago bundle --module Client --outfile client.js --platform browser
```


### Environment variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `CORPUS_USERS_FILE` | `users.json` | Path to the multi-user config file |
| `DATABASE_PATH` | _(cwd)_ | Root directory for all user database files |
| `PORT` | `8000` | HTTP port to listen on |
| `LASTFM_API_KEY` | — | Last.fm API key (required when any user has `lastfmUser` set; also used for genre and cover art fallback) |
| `DISCOGS_TOKEN` | — | Discogs token for cover art and genre fallback |
| `S3_BUCKET` | — | S3 bucket name for cover art caching and backups |
| `S3_REGION` | `us-east-1` | S3 region |
| `AWS_ACCESS_KEY_ID` | — | S3 credentials |
| `AWS_SECRET_ACCESS_KEY` | — | S3 credentials |
| `AWS_ENDPOINT_URL` | — | S3-compatible endpoint (e.g. for MinIO) |
| `AWS_S3_ADDRESSING_STYLE` | — | Set to `path` for path-style S3 URLs |
| `METRICS_ENABLED` | `false` | Set to `true` to expose Prometheus metrics at `/metrics` |

Per-user settings (`listenbrainzUser`, `lastfmUser`, `initialSync`, `coverCacheEnabled`, `backupEnabled`, `backupIntervalHours`, etc.) are configured in `users.json` (or `users.dhall`), not via environment variables.
