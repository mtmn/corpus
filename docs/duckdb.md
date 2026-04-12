# DuckDB in Scorpus

Scorpus uses [DuckDB](https://duckdb.org/) as its primary analytical database. DuckDB's columnar storage and efficient query engine allow Scorpus to provide fast filtering, pagination, and statistics over large sets of listening history data.

## Database Schema

The database consists of two main tables:

### `scrobbles`
Stores the raw listening history synced from ListenBrainz.

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

## Application Usage

The application interacts with DuckDB via a PureScript FFI layer (`src/Db.js` and `src/Db.purs`). 
- **BigInt Handling**: Since DuckDB returns `BIGINT` as JavaScript `BigInt`, the FFI layer converts these to `Number` to ensure compatibility with standard JSON serialization.
- **Background Enrichment**: The server identifies "unenriched" scrobbles (those with an MBID but no metadata) and performs background updates to the `release_metadata` table.

## Common Analytical Queries

You can run these queries directly against your `scorpus.db` file using the DuckDB CLI or any compatible tool.

### Top 10 Artists of All Time
```sql
SELECT artist_name, count(*) as play_count
FROM scrobbles
GROUP BY artist_name
ORDER BY play_count DESC
LIMIT 10;
```

### Listening Activity by Hour
```sql
SELECT 
    extract('hour' from to_timestamp(listened_at)) as hour, 
    count(*) as count
FROM scrobbles
GROUP BY hour
ORDER BY hour;
```

### Genre Distribution
```sql
SELECT rm.genre, count(*) as count
FROM scrobbles s
JOIN release_metadata rm ON s.release_mbid = rm.release_mbid
WHERE rm.genre IS NOT NULL
GROUP BY rm.genre
ORDER BY count DESC;
```

### MBID Enrichment Coverage
```sql
SELECT 
    count(*) as total,
    count(release_mbid) FILTER (WHERE release_mbid != '') as with_mbid,
    (count(release_mbid) FILTER (WHERE release_mbid != '')::FLOAT / count(*)) * 100 as percentage
FROM scrobbles;
```
