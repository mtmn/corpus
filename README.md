# Scorpus

| | |
| :--- | ---: |
| **Scorpus** is a personal [ListenBrainz](https://listenbrainz.org) dashboard. It syncs scrobbles, stores metadata in [DuckDB](https://duckdb.org), and caches cover art in S3 to provide a fast, searchable interface for your music history.<br><br>Features include automated syncing, rich metadata enrichment from MusicBrainz, and an interactive [PureScript](https://purescript.org)/Halogen frontend for deep exploration of your listening habits. | <img src="docs/korpus.webp" width="400" alt="Korpus"> |

## Documentation

- [Architecture](docs/architecture.md) — Deep dive into the system components, data flow, and FFI usage.
- [DuckDB](docs/duckdb.md) — Schema details, analytical queries, and tools for data exploration.

## Usage

This project uses [just](https://github.com/casey/just) and [Nix](https://nixos.org) for development and deployment.

### Development

```bash
# Enter the development shell (includes PureScript, DuckDB, etc.)
just shell

# Build the project (server and client)
just nix build

# Run the binary built by Nix
just nix run
```

### Spago Build (PureScript)

If you prefer to run PureScript commands manually:

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
- `LISTENBRAINZ_USER`: Your ListenBrainz username.
- `DATABASE_FILE`: Path to the DuckDB file (defaults to `scorpus.db`).
- `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, etc. (for cover art caching).
