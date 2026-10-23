# corpus

Corpus is a self-hosted listening history dashboard for ListenBrainz and Last.fm. It stores scrobbles in DuckDB, adds release metadata, caches cover art and serves an Elm web interface.

## Documentation

- [Architecture](docs/architecture.md): components, routes, data flows, configuration and operations
- [DuckDB](docs/duckdb.md): database schema
- [Example DuckDB queries](docs/duckdb_queries.md): statistics you can run against a user database

## Quick start

With Nix:

```sh
just shell
just nix build
just nix run
```

To build locally with pnpm:

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

`users.json` defines each static user's slug, source usernames, DuckDB filename, and cover and backup settings. Environment variables provide shared secrets and settings for other services.

| Variable | Purpose |
|---|---|
| `CORPUS_USERS_FILE` | Static user configuration (default: `users.json`) |
| `DATABASE_PATH` | Directory containing user databases |
| `LASTFM_API_KEY`, `DISCOGS_TOKEN` | Last.fm sync, and genre and cover fallbacks |
| `S3_BUCKET` and `AWS_*` | Cover cache and database backups |
| `COSINE_API_KEY` | Similar-track lookup |
| `PORT`, `HOST` | HTTP listener (defaults: `8000`, `127.0.0.1`) |
| `METRICS_ENABLED` | Enable Prometheus metrics at `/metrics` |

Set `REGISTRATION_ENABLED=true` to allow public registration at `/register`. Set `ADMIN_TOKEN` to enable approval at `/admin`. See the [configuration reference](docs/architecture.md#configuration-reference) for all settings, and [registration](docs/architecture.md#registration) for how approval works.

## Deploy to Fly.io

Nix builds the image. Fly runs it on one machine, with a volume at `/data` for the databases. See `fly.toml`.

First time, in `just shell`, with `FLY_APP` set to your app name:

```sh
flyctl auth login
flyctl apps create "$FLY_APP"
# skip settings that fly.toml sets, and empty values (they override defaults)
grep -vE '^(DATABASE_PATH|HOST|PORT|METRICS_ENABLED)=|=$' .env | flyctl secrets import --stage
```

Before the first deploy, put `users.json` and any existing databases on the volume. On Fly, Corpus reads `/data/users.json`, not the `users.json` in this repository.

Deploy:

```sh
just fly         # build with Nix, push to the Fly registry and deploy
just fly-push    # or only build and push
just fly-deploy  # or only deploy the image for the current source
```

Manage users:

```sh
flyctl ssh console -C "/bin/corpus-server list-users"
flyctl ssh console -C "/bin/corpus-server add-user --slug <slug> --db <file>"
flyctl apps restart "$FLY_APP"  # after add-user
```

`reset-token` fails while Corpus runs, because Corpus keeps the database open.
