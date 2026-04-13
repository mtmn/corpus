# Corpus Architecture

Corpus is a personal music listening history dashboard and analytics service. It synchronizes scrobbles from ListenBrainz and Last.fm and provides a performant web interface for data exploration and statistics.

## System Components

### Web Server
The server is built with PureScript running on Node.js. It handles several core responsibilities:
- **HTTP API**: Serves the frontend, scrobble data (with filtering/pagination), and statistics.
- **ListenBrainz Sync**: A background process that polls the ListenBrainz API every 60 seconds to fetch new scrobbles. Enabled when `LISTENBRAINZ_USER` is set.
- **Last.fm Sync**: A background process that polls the Last.fm API every 60 seconds to fetch new scrobbles. Enabled when `LASTFM_USER` and `LASTFM_API_KEY` are set. Both syncs write to the same `scrobbles` table; duplicate timestamps are silently ignored.
- **Metadata Enrichment**: A background process that identifies scrobbles with missing metadata (genres, labels, release years) and fetches information from MusicBrainz, Last.fm, and Discogs.
- **Cover Art Proxy**: A specialized endpoint that fetches, caches, and serves cover art, utilizing a multi-source fallback strategy (CAA → Last.fm → Discogs).

### Frontend
A Single Page Application (SPA) built with PureScript and the [Halogen](https://github.com/purescript-halogen/purescript-halogen) framework.
- **Real-time Updates**: Periodically refreshes the scrobble list.
- **Filtering & Search**: Supports deep filtering by genre, label, or release year.
- **Responsive UI**: Designed for both desktop and mobile viewing with a "retro-modern" aesthetic.

### Database
Corpus uses **DuckDB** for its primary data storage.
- **Schema**:
    - `scrobbles`: Stores the core listening history (timestamp, track, artist, album, MBIDs). The `listened_at` Unix timestamp is the primary key — scrobbles from ListenBrainz and Last.fm deduplicate naturally.
    - `release_metadata`: Stores enriched metadata indexed by MusicBrainz Release ID (MBID).
- **Performance**: DuckDB's columnar storage allows for extremely fast analytical queries across large listening histories.

### Storage
Uses an S3-compatible bucket to cache cover art images.
- **Caching Strategy**: Images are fetched once from external APIs and stored in S3 to reduce latency and avoid rate-limiting on external services.

## Data Flow

### Scrobble Synchronization

Both sync processes follow the same pattern: fetch the most recent page, insert any new scrobbles, and paginate backwards through history until an already-known timestamp is encountered.

**ListenBrainz** (timestamp-based pagination):
1. Fetch latest 100 scrobbles from the ListenBrainz API.
2. Insert new scrobbles; stop if an existing timestamp is found.
3. Paginate backwards using `max_ts` until fully caught up.

**Last.fm** (page-based pagination):
1. Fetch page 1 (most recent 200 scrobbles) from the Last.fm API.
2. Insert new scrobbles; stop if an existing timestamp is found.
3. Paginate through subsequent pages using `totalPages` from the API response until fully caught up.

Both processes run every 60 seconds. On subsequent syncs they stop at the first known timestamp, making incremental updates efficient.

### Metadata Enrichment
1. Background task identifies MBIDs in `scrobbles` that are not in `release_metadata`.
2. Queries MusicBrainz API for release details.
3. If MusicBrainz lacks genre information, falls back to Last.fm and Discogs APIs.
4. Updates `release_metadata` with found information.

### Cover Art Retrieval
When a cover is requested:
1. Check S3 cache.
2. If not found:
    - Try **Cover Art Archive (CAA)** using the Release MBID.
    - Fallback to **Last.fm** using Artist/Album name.
    - Final fallback to **Discogs** search API.
3. If found in any source, the image is proxied to the client and uploaded to S3 in the background.

## Tech Stack

- **Language**: [PureScript](https://purescript.org)
- **Frontend Framework**: [Halogen](https://github.com/purescript-halogen/purescript-halogen)
- **Runtime**: [Node.js](https://nodejs.org)
- **Database**: [DuckDB](https://duckdb.org)
- **Bundling**: [spago](https://github.com/purescript/spago) and [esbuild](https://esbuild.github.io/)
- **Environment**: [Nix](https://nixos.org) for reproducible development shells and container builds

## Foreign Function Interface (FFI)

Corpus relies on FFI to interact with the Node.js and browser ecosystems where native PureScript wrappers are unavailable or where direct JS access is required. Key FFI integrations include:

- **Database (`Db.js`)**: Provides a high-performance interface to the native `duckdb` library. It includes custom logic to handle BigInt conversions, ensuring database results are compatible with standard JSON serialization.
- **Cloud Storage (`S3.js`)**: Leverages the official AWS SDK (`@aws-sdk/client-s3`) to manage cover art caching in S3-compatible storage.
- **System Utilities (`Main.js`)**: Bridges PureScript with essential Node.js functionality, including environment variable management (`dotenv`) and raw buffer operations.

## System Flow

```mermaid
graph TD
    subgraph External APIs
        LB[ListenBrainz API]
        LF[Last.fm API]
        MB[MusicBrainz API]
        DC[Discogs API]
        CAA[Cover Art Archive]
    end

    subgraph Corpus Server
        LBSync[ListenBrainz Sync]
        LFSync[Last.fm Sync]
        Enrich[Enrichment Task]
        Proxy[Cover Proxy]
        API[Web API]
    end

    subgraph Storage
        DB[(DuckDB)]
        S3[[S3 Bucket]]
    end

    subgraph Frontend
        UI[Halogen SPA]
    end

    %% Scrobble Sync Flow
    LB -- "Fetch scrobbles" --> LBSync
    LBSync -- "Store scrobbles" --> DB
    LF -- "Fetch scrobbles" --> LFSync
    LFSync -- "Store scrobbles" --> DB

    %% Enrichment Flow
    DB -- "Get MBIDs" --> Enrich
    Enrich -- "Metadata" --> MB
    Enrich -- "1. Fallback Genre" --> LF
    Enrich -- "2. Fallback Genre" --> DC
    Enrich -- "Store Metadata" --> DB

    %% Web UI Flow
    UI -- "Request Data" --> API
    API -- "Query" --> DB
    DB -- "Results" --> API
    API -- "JSON" --> UI

    %% Cover Art Flow
    UI -- "Request Cover" --> Proxy
    Proxy -- "1. Check Cache" --> S3
    Proxy -- "2. Fallback CAA" --> CAA
    Proxy -- "3. Fallback Last.fm" --> LF
    Proxy -- "4. Fallback Discogs" --> DC
    Proxy -- "Cache Result" --> S3
    Proxy -- "Serve Image" --> UI
```
