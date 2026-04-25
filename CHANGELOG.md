# Changelog

## [2.8.1](https://github.com/mtmn/corpus/compare/v2.8.0...v2.8.1) (2026-04-25)


### Bug Fixes

* add corsOrigin config option ([3b8af96](https://github.com/mtmn/corpus/commit/3b8af96a105bafb36a7e27dbbc7d140438cce8e9))

## [2.8.0](https://github.com/mtmn/corpus/compare/v2.7.1...v2.8.0) (2026-04-24)


### Features

* add user mgmt commands ([d9c00d3](https://github.com/mtmn/corpus/commit/d9c00d357e271da9a447bdf0a4286bc15daf8109))
* deprecate .dhall users file, fmt ([60781e3](https://github.com/mtmn/corpus/commit/60781e32e4c3f284560aa788ffcf882f48b72da8))

## [2.7.1](https://github.com/mtmn/corpus/compare/v2.7.0...v2.7.1) (2026-04-24)


### Bug Fixes

* change cover cache order to caa=&gt;discogs=&gt;lastfm ([bd91c19](https://github.com/mtmn/corpus/commit/bd91c191491057e8b7870b0ceec744dba7aafb2c))
* count api in scrobbles metric ([ecd0ef6](https://github.com/mtmn/corpus/commit/ecd0ef63b24fcb59388bf5171bbcfbc5def26661))

## [2.7.0](https://github.com/mtmn/corpus/compare/v2.6.0...v2.7.0) (2026-04-23)


### Features

* add docs for submission endpoint ([964e6d2](https://github.com/mtmn/corpus/commit/964e6d21f7da17f059fe6d5b2ce6df659b4e4d31))
* add listenbrainz-like endpoint ([395689f](https://github.com/mtmn/corpus/commit/395689fd0a8f7bf63f58de5c15dc0ea5d0cda9a6))
* add tests for endpoint ([c723437](https://github.com/mtmn/corpus/commit/c723437e40f5c28e67f0ed191fd649fdf1d481fb))
* hash user token ([f42e52d](https://github.com/mtmn/corpus/commit/f42e52df18f6fd41d7b3645d0670f25e753f8425))
* lookup release json from caa before fetch ([91ac2f3](https://github.com/mtmn/corpus/commit/91ac2f3586e5fcb0cc58103b3e5f795a6ae7e255))
* simplify cover sources logic ([ad44c76](https://github.com/mtmn/corpus/commit/ad44c76150c0ca4b4d19036ee17f73d28d9ba06e))


### Bug Fixes

* add user-agent headers to fetchers ([2a8707f](https://github.com/mtmn/corpus/commit/2a8707f73f63011c034735ecba018ce753eb4550))
* wording in about ([d0e46ab](https://github.com/mtmn/corpus/commit/d0e46abeea9e0c61e31892bf8aaddff881e3bf43))

## [2.6.0](https://github.com/mtmn/corpus/compare/v2.5.1...v2.6.0) (2026-04-22)


### Features

* try various cover art sizes ([03a2a16](https://github.com/mtmn/corpus/commit/03a2a16595cea7816c8ab1c72f25c72001bf648b))


### Bug Fixes

* remove unused imports ([a32b34d](https://github.com/mtmn/corpus/commit/a32b34df7f24440e4b0a2d9d43d33ee6a79ee408))
* unhandled last.fm errors ([ef0cfc5](https://github.com/mtmn/corpus/commit/ef0cfc5adc80ef861db8afca6a5151fbb949b677))

## [2.5.1](https://github.com/mtmn/corpus/compare/v2.5.0...v2.5.1) (2026-04-22)


### Bug Fixes

* unhandled last.fm json serialization ([6415fc5](https://github.com/mtmn/corpus/commit/6415fc57d14f369c0d21d31194ee69f8cc186a7c))

## [2.5.0](https://github.com/mtmn/corpus/compare/v2.4.0...v2.5.0) (2026-04-22)


### Features

* convert to avif; decouple Client.elm ([55251a3](https://github.com/mtmn/corpus/commit/55251a3df4ae1af79e31e21203ceac62362527c0))
* decouple large files, convert to avif, housekeeping ([46449c4](https://github.com/mtmn/corpus/commit/46449c4d36488d151974818070168c9b9db2bc7c))
* doucple Main.purs to modules ([1f46d45](https://github.com/mtmn/corpus/commit/1f46d451909779255f150ecd9ac615b4e994895e))
* download large front covers from caa ([e1f768d](https://github.com/mtmn/corpus/commit/e1f768d457d9914f48049b036f45caa9a76d7ebd))
* move scrobbling logic to Sync.purs ([dc3828b](https://github.com/mtmn/corpus/commit/dc3828b48d0509f1e503693ae69329ae690a772a))


### Bug Fixes

* cache and convert cover art in the background ([e755708](https://github.com/mtmn/corpus/commit/e755708b80bf93f0520fb940b540f83578ec4aaa))
* remove initialSync param ([76ca97f](https://github.com/mtmn/corpus/commit/76ca97fd786c3e2e0e64422dcef0121275dcc552))
* remove unused imports; better logging ([1cf325d](https://github.com/mtmn/corpus/commit/1cf325d0a933e2e2e76d80a27bfed9cd847d8ce6))
* revert release-please gha ([4675ae2](https://github.com/mtmn/corpus/commit/4675ae2c5eb2344cbbae73ca5eadd00b28d5c781))
* run npmDepsHash job on each commit ([082bdf5](https://github.com/mtmn/corpus/commit/082bdf58b0974855e063adfe9b46183865018b41))

## [2.4.0](https://github.com/mtmn/corpus/compare/v2.3.1...v2.4.0) (2026-04-21)


### Features

* match colors to doric-obsidian ([2dff439](https://github.com/mtmn/corpus/commit/2dff439d76ee01df3471a570b507348acf5d267c))
* update user agents with github repo ([3d79cd7](https://github.com/mtmn/corpus/commit/3d79cd73c22979b5cb233437a7fea246cae328ca))

## [2.3.1](https://github.com/mtmn/corpus/compare/v2.3.0...v2.3.1) (2026-04-20)


### Bug Fixes

* missing selection for track and album ([ae926cd](https://github.com/mtmn/corpus/commit/ae926cd79f917e5ed298aad0cff70830fb682198))

## [2.3.0](https://github.com/mtmn/corpus/compare/v2.2.0...v2.3.0) (2026-04-20)


### Features

* add track filter and make all filters clickable ([424e247](https://github.com/mtmn/corpus/commit/424e247b8f4ce94d373d1dca220dc05555c0c0cb))

## [2.2.0](https://github.com/mtmn/corpus/compare/v2.1.1...v2.2.0) (2026-04-19)


### Features

* add about section ([70a9598](https://github.com/mtmn/corpus/commit/70a9598c92502e930f193b87d49961b070deea43))
* add about, labels and fix search ([616884d](https://github.com/mtmn/corpus/commit/616884dc5a43105dd11e4a500dc282d0df13fef6))
* add custom user name, fixes ([704cce1](https://github.com/mtmn/corpus/commit/704cce17520c36c66ac853323ad5764a2c16ccf8))
* add search to listens section ([7eeea36](https://github.com/mtmn/corpus/commit/7eeea36d2f193271daf10b9db98e1dd11a2e236d))
* change user slug, fixes ([0661ae7](https://github.com/mtmn/corpus/commit/0661ae7e6ef426453a33fd119d6ceb101ba6f40b))
* scrobbles searchable by album ([4c1a772](https://github.com/mtmn/corpus/commit/4c1a7721dd7ebb9995a348efa383798492661cb6))
* scrobbles searchable by album ([376ec03](https://github.com/mtmn/corpus/commit/376ec03a0338f84ec79c33377029ca8d92bd06b6))
* shutdown handling, fix race conditions ([f397076](https://github.com/mtmn/corpus/commit/f397076870e8c54ccca437a591a2090ca87de917))
* shutdown handling, fix race conditions ([b1dc26e](https://github.com/mtmn/corpus/commit/b1dc26e42cc45630af4cd116e212c55e315cbbd7))


### Bug Fixes

* add label to tests ([601c8e5](https://github.com/mtmn/corpus/commit/601c8e57af116fad0f2ea860f9da10b8fd40b7c2))
* missing doc entries ([eddc3f7](https://github.com/mtmn/corpus/commit/eddc3f70a2591410612fe5e0db471958d40233f3))

## [2.1.1](https://github.com/mtmn/corpus/compare/v2.1.0...v2.1.1) (2026-04-19)


### Bug Fixes

* make css less whimsical, i think ([16c92be](https://github.com/mtmn/corpus/commit/16c92be3c1d5a3ab72b74cd5b282e17c25ee82d0))

## [2.1.0](https://github.com/mtmn/corpus/compare/v2.0.0...v2.1.0) (2026-04-19)


### Features

* add grafana dashboard ([0ec0b97](https://github.com/mtmn/corpus/commit/0ec0b976fc7e19ed5790ca050feec1cdd277547a))

## [2.0.0](https://github.com/mtmn/corpus/compare/v1.4.0...v2.0.0) (2026-04-19)


### ⚠ BREAKING CHANGES

* remove otel, add cosine.club metrics

### Features

* remove otel, add cosine.club metrics ([e7cb4e5](https://github.com/mtmn/corpus/commit/e7cb4e51e3a7ecd8e1cde6bd20777031d162a63c))

## [1.4.0](https://github.com/mtmn/corpus/compare/v1.3.1...v1.4.0) (2026-04-19)


### Features

* integrate cosine.club api ([cad0dd8](https://github.com/mtmn/corpus/commit/cad0dd8574c4951e4be9de041dca97a33d1c0496))

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
