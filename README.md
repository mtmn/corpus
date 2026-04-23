# corpus
A self-hosted [ListenBrainz](https://listenbrainz.org) and [Last.fm](https://last.fm) frontend that stores metadata and cover images.

It includes storing scrobbles, metadata enrichment, and an interactive [PureScript](https://purescript.org) frontend for exploration of your listening habits.

You can see it for yourself - [scrobbler.mtmn.name](https://scrobbler.mtmn.name)

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
npm install
npx spago install

# Build the project
npm run build

# Run tests
npx spago test

# Build an optimized release
npm run release

# Run the application
npx spago run
```

### Scrobbling API

Corpus provides a [ListenBrainz-compatible](https://listenbrainz.readthedocs.io/en/latest/users/api-resources.html#post--1-submit-listens) endpoint for submitting scrobbles directly. This allows you to use any scrobbler that supports custom ListenBrainz endpoints (like [Pano Scrobbler](https://github.com/kawaiiDoge/PanoScrobbler) or [Simple Scrobbler](https://github.com/waicool20/Simple-Scrobbler)).

#### Endpoint

`POST /1/submit-listens`

#### Authentication

The API uses token-based authentication. A unique API token is automatically generated for each user when they first start the application. You can find your token in the server logs on startup:

```text
[INFO] User 'mtmn' token: 550e8400-e29b-41d4-a716-446655440000
```

Include the token in the `Authorization` header of your requests:

```text
Authorization: Token <your-token>
```

#### Payload Format

The endpoint accepts standard ListenBrainz JSON payloads. See the [ListenBrainz API documentation](https://listenbrainz.readthedocs.io/en/latest/users/api-resources.html#post--1-submit-listens) for details.

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
| `COSINE_API_KEY` | — | [cosine.club](https://cosine.club) API key for similar tracks |
| `METRICS_ENABLED` | `false` | Set to `true` to expose Prometheus metrics at `/metrics` |

### Per-user configuration

| Field | Default | Description |
| :--- | :--- | :--- |
| `slug` | — | URL slug (`""` for root user, `"filip"` for `/u/filip`) |
| `name` | — | Display name for the user (defaults to slug if not provided) |
| `listenbrainzUser` | — | ListenBrainz username to sync scrobbles from |
| `lastfmUser` | — | Last.fm username to sync scrobbles from |
| `databaseFile` | `corpus.db` | Path to the user's DuckDB database file |
| `coverCacheEnabled` | `true` | Enable cover art caching to S3 |
| `backupEnabled` | `false` | Enable database backups to S3 |
| `backupIntervalHours` | `24` | Backup frequency in hours |
