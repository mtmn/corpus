# Changelog

## [1.3.1](https://github.com/mtmn/corpus/compare/v1.3.0...v1.3.1) (2026-04-18)


### Bug Fixes

* initialSync halts syncing, broken range query ([720e234](https://github.com/mtmn/corpus/commit/720e2341ba1bd1b8482be75d9246544f12d98e3f))

## [1.3.0](https://github.com/mtmn/corpus/compare/v1.2.0...v1.3.0) (2026-04-18)


### Features

* rewrite into folds, cover/genre rewrite ([bd17786](https://github.com/mtmn/corpus/commit/bd17786cbf22fec6accecf887e313fd4f9ed6c16))


### Bug Fixes

* update tests ([04d8f23](https://github.com/mtmn/corpus/commit/04d8f234eb6735ce689c7112350bd435efc4f677))

## [1.2.0](https://github.com/mtmn/corpus/compare/v1.1.1...v1.2.0) (2026-04-18)


### Features

* add backups, enabled params ([1e6c54e](https://github.com/mtmn/corpus/commit/1e6c54e9c2e7f92435dc852a8eb4a5d1d1c13555))
* add filters, allow show all ([98a7d90](https://github.com/mtmn/corpus/commit/98a7d9015b130b10d547879bf7c4f97564119045))
* add lastfm support ([30a5b09](https://github.com/mtmn/corpus/commit/30a5b09979f89a000349f8b0a1d4a01c366b0b37))
* add logging, housekeeping ([256fabd](https://github.com/mtmn/corpus/commit/256fabd6c694cf3baa9b4aed99054856b3e3ad8d))
* add metrics endpoint ([7778b2f](https://github.com/mtmn/corpus/commit/7778b2f51bb2535961430c68e07976a618574f98))
* add more tests, update justfile ([a661ea7](https://github.com/mtmn/corpus/commit/a661ea755876178185f024fbf3ae49799c7d0fe0))
* add otel tracing ([5c66597](https://github.com/mtmn/corpus/commit/5c66597e586f5737c251624670c24c773616994c))
* add stats ([84de966](https://github.com/mtmn/corpus/commit/84de9664f3879aa99f1de2f6e205b472a4f7aa62))
* add support for defining users ([cbad3c9](https://github.com/mtmn/corpus/commit/cbad3c94ae8ef2ee34f00b53a2d46b2aa01675a9))
* add tag hover ([a6f5c58](https://github.com/mtmn/corpus/commit/a6f5c58df7f6bb73d0c23f10e3e0eee8974a5c6b))
* add tests ([3651727](https://github.com/mtmn/corpus/commit/3651727e9b874ff1ccd9d465cedb7087ce6b3c0d))
* add tests and update readme ([4f05117](https://github.com/mtmn/corpus/commit/4f051176f953dbe351732a360f9b2399c9201e01))
* add write locks to db ([3a65b1d](https://github.com/mtmn/corpus/commit/3a65b1d22b79f30adc09247979c6730c524c33a1))
* **ci:** add nix flake ([371647e](https://github.com/mtmn/corpus/commit/371647e2d881e595dc9585b4f75f5b7413c5d50f))
* deduplicate cover fetching logic ([e989bba](https://github.com/mtmn/corpus/commit/e989bba045f4fd9e8840311a1c7d72da4044a987))
* duckdb chepoint to a bucket ([9ce663e](https://github.com/mtmn/corpus/commit/9ce663eb3af0ff7a7d55a46f2b9794d0b8e3b46a))
* duckdb, blob storage, pagination ([2ebcce9](https://github.com/mtmn/corpus/commit/2ebcce9a7d76943d8458dc7c14f1ea88b2494c71))
* duckdb, blob storage, pagination ([81b875d](https://github.com/mtmn/corpus/commit/81b875db673b21a17d2eb03ba3bc0ee856beece4))
* fix builds, inline htmx to ps-halogen ([eeea67c](https://github.com/mtmn/corpus/commit/eeea67c5bc81b7c40a8d9f3056688827534b3b6e))
* fix builds, inline htmx to ps-halogen ([e394d45](https://github.com/mtmn/corpus/commit/e394d45dba7c024d0a5057945d4261fe623c8048))
* improve logging ([920d79e](https://github.com/mtmn/corpus/commit/920d79e9006d489c388aad52c0f7403ff878c2b1))
* periodic scans, disable source builds, docs ([0b16f34](https://github.com/mtmn/corpus/commit/0b16f34cd0b26cbc536e1ca81b95878777722e16))
* **stats:** add custom date range ([4dbe257](https://github.com/mtmn/corpus/commit/4dbe257a4a042d3ce2db368c628cf446a9831308))
* **stats:** add show all expander ([1cb57f7](https://github.com/mtmn/corpus/commit/1cb57f77c713a3dc32809c58d64f56462c49ab68))
* use elm in frontend instead of halogen ([4824c51](https://github.com/mtmn/corpus/commit/4824c5183b7569c0b6832e17bf2997f844cca7a8))
* use elm in frontend instead of halogen ([d14b003](https://github.com/mtmn/corpus/commit/d14b0037e384f11422e4aad79cc77b7f4d7160e2))
* zoom on hover for covers, bugfixes ([6765dd1](https://github.com/mtmn/corpus/commit/6765dd11226324d71174457025cc5438831b39f8))


### Bug Fixes

* add build step, leaky queries ([c32d695](https://github.com/mtmn/corpus/commit/c32d695364fa17afe8ea3374bd247ad043a9f9d8))
* default database path to cwd ([7c6cb72](https://github.com/mtmn/corpus/commit/7c6cb72805f95fe9dd9cbe2bd4f48c76f387b7b7))
* dont block startUser on sync ([d23cdc4](https://github.com/mtmn/corpus/commit/d23cdc44614ea1ecc2f6502adf1c2d55e6ceda48))
* **elm:** expose only necessary html tags ([186ec6a](https://github.com/mtmn/corpus/commit/186ec6a3a96d7a3a393402712c574022ab58096f))
* **elm:** expose only necessary html tags ([242526a](https://github.com/mtmn/corpus/commit/242526a56e02bd503939cb3e161038191c412d36))
* flaky tests, ignore results ([f7df563](https://github.com/mtmn/corpus/commit/f7df56365ed9263689100ff87476cb8541593b16))
* get rid of regex interop functions ([d968e33](https://github.com/mtmn/corpus/commit/d968e3386853312e1a898c0be2bf7d4d2c31bd46))
* gha backoff on error ([97f3628](https://github.com/mtmn/corpus/commit/97f3628728f89ba58874d2b9e9ca9bc8efd38085))
* instrument complete HTTP span ([4a143e7](https://github.com/mtmn/corpus/commit/4a143e7c4629acfdf0f1e4f1b49f09c5af8c2286))
* move template to a separate file ([4f100bd](https://github.com/mtmn/corpus/commit/4f100bd2a3173124e7ab0437337245b3585a1b5b))
* move user to config, click listens go home ([b28582a](https://github.com/mtmn/corpus/commit/b28582a2e8bfd836184de4c65034f06c8b845ce6))
* open cover on click, genre tag css ([774ae94](https://github.com/mtmn/corpus/commit/774ae9481544bcbcd49becd286aa58769488d8da))
* optimize client.js output ([5a1fb85](https://github.com/mtmn/corpus/commit/5a1fb8543495e882b6de36f4d6a3c5674676c405))
* sanitize duckdb queries ([066a69f](https://github.com/mtmn/corpus/commit/066a69ffd1212153a071ef4007a1b8264d10a443))
* sanitize log output; remove cors ([54b1223](https://github.com/mtmn/corpus/commit/54b12233a08db330ec8a99bccca135c3f51a423e))
* update docs; add metrics switch, fixes ([00b1982](https://github.com/mtmn/corpus/commit/00b198265b744a7042e70e31fb7a71925c9166fd))
* update nix hashes ([7899031](https://github.com/mtmn/corpus/commit/78990317aaf6a7f7cd626bd8a9794090c8391657))
* use native ps for url handling ([4831a6c](https://github.com/mtmn/corpus/commit/4831a6c786163667409283b778a10ce69571a5b9))
* yeild request when duckdb connection is present ([d3bfafb](https://github.com/mtmn/corpus/commit/d3bfafb7410299316b288e7d29e02634aedfc8b4))

## [1.1.1](https://github.com/mtmn/corpus/compare/v1.1.0...v1.1.1) (2026-04-18)


### Bug Fixes

* add build step, leaky queries ([c32d695](https://github.com/mtmn/corpus/commit/c32d695364fa17afe8ea3374bd247ad043a9f9d8))
* gha backoff on error ([97f3628](https://github.com/mtmn/corpus/commit/97f3628728f89ba58874d2b9e9ca9bc8efd38085))
* sanitize log output; remove cors ([54b1223](https://github.com/mtmn/corpus/commit/54b12233a08db330ec8a99bccca135c3f51a423e))
