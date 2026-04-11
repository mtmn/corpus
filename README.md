# Scorpus

| | |
| :--- | ---: |
| Scorpus is a ListenBrainz frontend built with PureScript that provides server-side rendering and client-side interactivity using Halogen. It enables music listening tracking with DuckDB/SQLite storage and S3 integration for data management. | <img src="docs/korpus.webp" width="400" alt="Korpus"> |

---

## Architecture

### Client-Side (Browser)

- **Halogen** — Component-based UI framework for declarative, reactive interfaces
- **Affjax / Fetch** — HTTP client for API communication with the backend
- **Argonaut** — JSON encoding/decoding for structured data exchange
- **Web HTML / DOM** — Low-level browser API bindings for direct DOM manipulation

### Server-Side (Node.js)

- **Node HTTP** — Built-in Node.js HTTP server for request handling
- **DuckDB / SQLite3** — Embedded analytical and transactional databases for music listening data
- **AWS S3 SDK** — Object storage integration for large-scale data export/import
- **Environment Config** — Dotenv-based configuration management

### Shared

- **PureScript 0.15** — Strongly-typed functional language compiled to JavaScript
- **Esbuild** — Fast bundler producing both server (Node ESM) and client (browser) bundles
- **Spago** — PureScript package manager and build tool
- **Argonaut Core** — Shared JSON serialization layer across client and server
