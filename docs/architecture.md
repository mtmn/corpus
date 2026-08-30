# Corpus architecture

Corpus is a self-hosted listening history dashboard. It synchronises ListenBrainz and Last.fm scrobbles for multiple users.

## System components

### Web server
The PureScript server runs on Node.js. It:

- serves the frontend, scrobble data, statistics and similar tracks from [cosine.club](https://cosine.club)
- accepts ListenBrainz-compatible scrobble submissions
- polls ListenBrainz and Last.fm every 60 seconds
- deduplicates matching timestamps using the `listened_at` primary key
- enriches missing genres, labels and release years from MusicBrainz, Last.fm and Discogs
- redirects and caches cover art, trying Cover Art Archive, Discogs and then Last.fm
- provides optional registration, administration, email and Prometheus metrics

External API requests time out after 10 seconds. Image requests time out after 20 seconds.

### Frontend
The Elm single-page application:

- refreshes the scrobble list periodically
- filters by genre, label or release year
- searches tracks, artists, albums and labels
- links listen metadata to matching filters
- works on desktop and mobile

### Database
Corpus stores each user's data in a separate DuckDB file:

- `scrobbles` stores listening history with `listened_at` as its primary key
- `release_metadata` stores genre, label and release year by MusicBrainz release ID
- `api_tokens` stores SHA-256 hashes of submission tokens

DuckDB's columnar storage supports analytical queries over large listening histories.

### Storage
Corpus uses an S3-compatible bucket when you enable cover caching or backups:

- the cover cache stores AVIF images and redirects hits to presigned S3 URLs
- backups checkpoint a user's DuckDB file and upload timestamped snapshots
- the shared `registrations.db` file stores pending, approved, denied and revoked registrations

## Multi-user support

Corpus serves multiple users from one process. Use the command-line interface to manage static users in `users.json`.

### Routes

Corpus provides these routes:

- `/` and `/u/<slug>`: serve the Elm application for the root user and named users
- `/proxy?user=<slug>`, `/stats?user=<slug>`, `/cover?user=<slug>`, `/similar?user=<slug>`: select a user through the query parameter
- `/healthz?user=<slug>`: checks the user's DuckDB connection
- `/1/validate-token`: validates a ListenBrainz-compatible token
- `/1/submit-listens`: accepts ListenBrainz-compatible submissions with an `Authorization: Token <token>` header
- `/register` and `/admin`: serve registration and administration pages
- `/metrics`: returns metrics for all users when `METRICS_ENABLED=true`

Set `REGISTRATION_ENABLED=true` to enable registration. Set `ADMIN_TOKEN` to enable the administration APIs.

### User management

Stop Corpus before using these commands to change `users.json`:

```sh
# Add a new user (creates the DB, prints the API token once)
node server.js add-user --slug filip --name "Filip" --db filip.db

# Optional: link a ListenBrainz or Last.fm account at creation time
node server.js add-user --slug filip --name "Filip" --db filip.db \
  --listenbrainz-user filip --lastfm-user filiplfm

# List all users
node server.js list-users

# Regenerate the API token for a user
node server.js reset-token --slug filip
```

Corpus prints the API token once when you create or reset a user. Store it securely. Send it to `/1/submit-listens` as `Authorization: Token <token>`.

### Configuration
User configuration has 2 layers:

1. `users.json` defines user slugs, source usernames, database filenames and feature flags. The CLI manages this file. Corpus reads it at startup from `CORPUS_USERS_FILE`, which defaults to `users.json`.
2. Environment variables provide shared API keys and S3 credentials at runtime.

Each user has a separate DuckDB connection, sync loop and write lock. The lock runs ListenBrainz and Last.fm sync transactions in sequence. HTTP reads use DuckDB snapshots without taking the lock.

Corpus provisions approved registrations immediately and reloads them from `registrations.db` at startup. It does not change `users.json`. A `users.json` entry takes precedence over a registration with the same slug.

### Remove registered users

An administrator can remove a self-registered user without restarting Corpus. Corpus stops their background work, closes and deletes their DuckDB file, then revokes the registration. Administrators cannot use this process for users defined in `users.json`.

## Configuration reference

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CORPUS_USERS_FILE` | `users.json` | Path to the user configuration file |
| `DATABASE_PATH` | _(cwd)_ | Root directory for all user database files |
| `LASTFM_API_KEY` | not set | Last.fm API key (required if any user has `lastfmUser`) |
| `DISCOGS_TOKEN` | not set | Discogs token for cover and genre fallback |
| `S3_BUCKET` | not set | S3 bucket for cover art cache |
| `S3_REGION` | `us-east-1` | S3 region |
| `AWS_ACCESS_KEY_ID` | not set | S3 credentials |
| `AWS_SECRET_ACCESS_KEY` | not set | S3 credentials |
| `AWS_ENDPOINT_URL` | not set | S3-compatible endpoint |
| `AWS_S3_ADDRESSING_STYLE` | not set | `virtual` or `path` |
| `COSINE_API_KEY` | not set | [cosine.club](https://cosine.club) API key for similar tracks |
| `PORT` | `8000` | HTTP listen port |
| `HOST` | `127.0.0.1` | HTTP listen host |
| `METRICS_ENABLED` | `false` | Set to `true` to enable `/metrics` |
| `CORS_ORIGIN` | `*` | Value of `Access-Control-Allow-Origin` on `/proxy` responses |
| `REGISTRATION_ENABLED` | `false` | Set to `true` to enable public registration at `/register` |
| `ADMIN_TOKEN` | not set | Bearer token for `/admin/*`; these routes return 404 when unset |
| `ADMIN_EMAIL` | not set | Address notified of new registration requests |
| `CORPUS_REGISTRATIONS_DB` | `registrations.db` | Shared DuckDB file for registration state |
| `SMTP_HOST` | not set | SMTP server host; Corpus skips email when unset |
| `SMTP_PORT` | `587` | SMTP port (STARTTLS) |
| `SMTP_USER` | not set | SMTP username |
| `SMTP_PASS` | not set | SMTP password |
| `SMTP_FROM` | not set | Sender address |

Set `LASTFM_API_KEY` when any user has `lastfmUser`. Cover caching and backups require `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINT_URL`.

### `users.json` fields

`slug` and `name` belong to each item in `users`. Put the other fields in its `config` object. Only `name`, `listenbrainzUser` and `lastfmUser` are optional.

| Field | Type | Purpose |
|---|---|---|
| `slug` | string | URL slug (`""` for the root user, `"filip"` for `/u/filip`) |
| `name` | optional string | Display name, which defaults to the slug |
| `listenbrainzUser` | optional string | ListenBrainz username |
| `lastfmUser` | optional string | Last.fm username |
| `databaseFile` | string | DuckDB filename, relative to `DATABASE_PATH` |
| `coverCacheEnabled` | boolean | Enables S3 cover caching |
| `backupEnabled` | boolean | Enables periodic S3 database backups |
| `backupIntervalHours` | integer | Hours between backups |

## Data flow

### Scrobble synchronisation

Both sync processes fetch the newest page, insert new scrobbles and move backwards until they find a known timestamp.

ListenBrainz uses timestamp-based pagination:
1. Fetch latest 100 scrobbles from the ListenBrainz API.
2. Insert new scrobbles. Stop if an existing timestamp is found.
3. Paginate backwards using `max_ts` until fully caught up.

Last.fm uses page-based pagination:
1. Fetch page 1 (most recent 200 scrobbles) from the Last.fm API.
2. Insert new scrobbles. Stop if an existing timestamp is found.
3. Paginate through subsequent pages using `totalPages` from the API response until fully caught up.

Both processes run every 60 seconds for each user. Later syncs stop at the first known timestamp.

### Metadata enrichment

1. Corpus finds release MBIDs that do not have metadata.
2. It requests release details from MusicBrainz.
3. If MusicBrainz has no genre, it tries Last.fm and Discogs.
4. It updates `release_metadata` with any details found.

### Cover art retrieval
When a client requests a cover:

1. Corpus checks the S3 cache.
2. On a miss, Corpus tries Cover Art Archive, Discogs and then Last.fm.
3. Corpus redirects the client immediately. If caching is enabled, it converts and uploads the image in the background.

## Observability

### Prometheus metrics

Prometheus metrics are disabled by default. Set `METRICS_ENABLED=true` to record HTTP requests and background work. When disabled, `/metrics` returns 404 and metric calls do nothing.

| Metric | Type | Labels | Description |
|---|---|---|---|
| `corpus_http_requests_total` | Counter | `method`, `path`, `status` | HTTP requests |
| `corpus_http_request_duration_seconds` | Histogram | `method`, `path` | HTTP request latency |
| `corpus_sync_runs_total` | Counter | `user`, `source`, `result` | Sync loop iterations |
| `corpus_sync_scrobbles_added_total` | Counter | `user`, `source` | Scrobbles inserted per sync |
| `corpus_sync_last_success_seconds` | Gauge | `user`, `source` | Timestamp of last successful sync |
| `corpus_enrichment_fetches_total` | Counter | `user`, `source`, `result` | Metadata enrichment API calls |
| `corpus_enrichment_queue_size` | Gauge | `user`, `type` | Releases pending enrichment |
| `corpus_cover_requests_total` | Counter | `user`, `source`, `result` | Cover art requests |
| `corpus_cosine_requests_total` | Counter | `user`, `result` | Similar-track lookup requests |
| `corpus_db_backup_runs_total` | Counter | `user`, `result` | Database backup runs |
| `corpus_db_backup_last_success_seconds` | Gauge | `user` | Timestamp of last successful backup |

`prom-client` also collects Node.js garbage collection, event loop and memory metrics.

## Tech stack

- server language: [PureScript](https://purescript.org)
- frontend language: [Elm](https://elm-lang.org)
- runtime: [Node.js](https://nodejs.org)
- database: [DuckDB](https://duckdb.org), with one file for each user
- configuration: JSON in `users.json`, managed through the command-line interface
- bundling: [Spago](https://github.com/purescript/spago), [esbuild](https://esbuild.github.io/) and [elm make](https://guide.elm-lang.org/install/elm.html)
- build environment: [Nix](https://nixos.org)

## Foreign function interface

Corpus uses JavaScript modules where no PureScript wrapper is available:

- `Db.js` uses `@duckdb/node-api` and converts JavaScript `BigInt` values to `Number` for JSON
- `S3.js` uses `@aws-sdk/client-s3` for cover caching
- `Main.js` loads `.env` files and provides request helpers
- `Config.js` reads and parses the file set by `CORPUS_USERS_FILE`
- `Metrics.js` uses `prom-client` to record HTTP and background-work metrics

## System flow

See [`architecture.dot`](architecture.dot) (render with `just docs`).

![System flow](architecture.svg)
