# DuckDB in Corpus

Corpus stores each user's listening history in [DuckDB](https://duckdb.org/). Its columnar query engine supports filtering, pagination and statistics over large histories.

## Database schema

Each user has a separate DuckDB database file with 3 tables. A shared `registrations.db` file holds registration state.

### `scrobbles`
Stores listening history from ListenBrainz and Last.fm.

| Column | Type | Description |
| :--- | :--- | :--- |
| `listened_at` | BIGINT | Unix timestamp (primary key) |
| `track_name` | VARCHAR | Track name |
| `artist_name` | VARCHAR | Artist name |
| `release_name` | VARCHAR | Album or release name |
| `release_mbid` | VARCHAR | MusicBrainz release ID |
| `caa_release_mbid` | VARCHAR | Cover Art Archive release ID |

### `release_metadata`
Stores metadata fetched from MusicBrainz, Last.fm and Discogs.

| Column | Type | Description |
| :--- | :--- | :--- |
| `release_mbid` | VARCHAR | MusicBrainz release ID (primary key) |
| `genre` | VARCHAR | Primary genre |
| `label` | VARCHAR | Record label |
| `release_year` | INTEGER | Year of release |
| `genre_checked_at` | INTEGER | Unix timestamp of the last genre lookup that found nothing |

Corpus looks for a missing genre again 7 days after `genre_checked_at`.

### `api_tokens`
Stores hashed API tokens for scrobble submission.

| Column | Type | Description |
| :--- | :--- | :--- |
| `slug` | VARCHAR | User slug (primary key) |
| `hashed_token` | VARCHAR | SHA-256 hash of the API token (unique) |

### `registrations`
Stores self-registration requests in the shared `registrations.db` file, not in the user databases.

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | VARCHAR | Registration UUID (primary key) |
| `slug` | VARCHAR | Requested username |
| `display_name` | VARCHAR | Display name |
| `email` | VARCHAR | Contact email address |
| `listenbrainz_user` | VARCHAR | ListenBrainz username |
| `lastfm_user` | VARCHAR | Last.fm username |
| `status` | VARCHAR | `pending`, `approved`, `denied` or `revoked` |
| `created_at` | BIGINT | Unix timestamp of the request |
| `decided_at` | BIGINT | Unix timestamp of the last status change |

## Application use

Corpus accesses DuckDB through `src/Db.purs` and `src/Db.js`:

- the JavaScript layer converts DuckDB `BIGINT` values to `Number` for JSON serialisation
- the server finds releases that have no metadata or no genre, then updates `release_metadata`
- backups run `CHECKPOINT` before uploading a database file

Use the [example DuckDB queries](duckdb_queries.md) with the DuckDB command-line interface or another compatible tool.
