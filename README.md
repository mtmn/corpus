# Corpus

| | |
| :--- | ---: |
| **Corpus** is an alternative [ListenBrainz](https://listenbrainz.org) (Last.fm planned for the future) frontend that stores metadata and cover images.<br><br>Includes scrobbles fetching, metadata enrichment, and an interactive [PureScript](https://purescript.org) frontend for exploration of your listening habits.<br><br>[Live instance running here.](https://scrobbler.mtmn.name) | <img src="docs/korpus.webp" width="400" alt="Korpus"> |

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


Required environment variables:
- `LISTENBRAINZ_USER`: Your ListenBrainz username
- `DATABASE_FILE`: Path to the DuckDB file (defaults to `corpus.db`)
- `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, etc. (for cover art caching)
