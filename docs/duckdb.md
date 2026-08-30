# DuckDB in Corpus

Corpus stores each user's listening history in [DuckDB](https://duckdb.org/). Its columnar query engine supports filtering, pagination and statistics over large histories.

## Database schema

Each user has an independent DuckDB database file. That database consists of three main tables:

### `scrobbles`
Stores listening history from ListenBrainz and Last.fm.

| Column | Type | Description |
| :--- | :--- | :--- |
| `listened_at` | BIGINT | Unix timestamp (Primary Key) |
| `track_name` | VARCHAR | Name of the track |
| `artist_name` | VARCHAR | Name of the artist |
| `release_name` | VARCHAR | Name of the album/release |
| `release_mbid` | VARCHAR | MusicBrainz Release ID |
| `caa_release_mbid` | VARCHAR | Cover Art Archive Release ID |

### `release_metadata`
Stores enriched metadata fetched from MusicBrainz, Last.fm, and Discogs.

| Column | Type | Description |
| :--- | :--- | :--- |
| `release_mbid` | VARCHAR | MusicBrainz Release ID (Primary Key) |
| `genre` | VARCHAR | Primary genre |
| `label` | VARCHAR | Record label |
| `release_year` | INTEGER | Year of release |
| `genre_checked_at` | INTEGER | Timestamp of last enrichment attempt |

### `api_tokens`
Stores hashed user API tokens for scrobble submission.

| Column | Type | Description |
| :--- | :--- | :--- |
| `slug` | VARCHAR | User slug (Primary Key) |
| `hashed_token` | VARCHAR | SHA-256 hash of the API token (Unique) |

Self-registration state is intentionally kept outside the per-user databases in the shared `registrations.db` file. It is managed by the server rather than by the listening-history schema.

## Application use

Corpus accesses DuckDB through `src/Db.purs` and `src/Db.js`:

- the JavaScript layer converts DuckDB `BIGINT` values to `Number` for JSON serialisation
- the server finds scrobbles with a release MBID but no metadata, then updates `release_metadata`

Use the [example DuckDB queries](duckdb_queries.md) with the DuckDB command-line interface or another compatible tool.
