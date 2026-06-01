# Changelog

## [2.17.1] - 2026-06-01

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.17.0..v2.17.1)

### Bug Fixes

- Replace `unsafeRegex` clauses ([`be7ee69`](https://git.sr.ht/~mtmn/corpus/commit/be7ee69398cc6aef5989dcf92340e7fc323517a6))
- Guarantee lock release in db transaction ([`84a7307`](https://git.sr.ht/~mtmn/corpus/commit/84a7307cd1eb5d243fbbd35e1f3f853ffe950018))
- Better type safety ([`96b22d1`](https://git.sr.ht/~mtmn/corpus/commit/96b22d1c3a5e8459c4807eb86d06533a48233cfb))
- Deduplicate sql logic; separate Handler.purs ([`612dceb`](https://git.sr.ht/~mtmn/corpus/commit/612dcebd7ae4f62ddb284a5d6b3a933e7da3c11a))

### Housekeeping

- Add purs-tidy config ([`12fde33`](https://git.sr.ht/~mtmn/corpus/commit/12fde33d119bb89bc332c4e17551d03feeadb328))
- Fix whines ([`a70f22f`](https://git.sr.ht/~mtmn/corpus/commit/a70f22f7593ebae3974c4b7cd56e40dbb68de2e5))

## [2.17.0] - 2026-05-31

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.16.1..v2.17.0)

### Bug Fixes

- Improve nix builds ([`1589114`](https://git.sr.ht/~mtmn/corpus/commit/158911443a5ad991d41008570297de98b413e041))

### Features

- Use elm2nix fork with lix support ([`09e694c`](https://git.sr.ht/~mtmn/corpus/commit/09e694ceacbbfdf1aea32cdff1ce2a929e98e67a))

### Housekeeping

- Switch to nixpkgs-unstable ([`b3a4a1b`](https://git.sr.ht/~mtmn/corpus/commit/b3a4a1bfb44072409696b2d9d244f6d739fd9466))
- Release v2.17.0 ([`d750f9f`](https://git.sr.ht/~mtmn/corpus/commit/d750f9f7aab43a912871d96eadb2ebd5254e09c4))

## [2.16.1] - 2026-05-23

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.16.0..v2.16.1)

### Housekeeping

- Add garnix badge to readme ([`63d299d`](https://git.sr.ht/~mtmn/corpus/commit/63d299dcefb65a87315c770bad44a20b25d8b01e))
- Comment out whine from checks ([`fb31b79`](https://git.sr.ht/~mtmn/corpus/commit/fb31b7914e275fe1a6b412dd66d40581b3faf071))
- Bump flakes and version ([`b640141`](https://git.sr.ht/~mtmn/corpus/commit/b6401415afb65c87969b5328d7af8447a7d42f9e))
- Release v2.16.1 ([`a2ab60a`](https://git.sr.ht/~mtmn/corpus/commit/a2ab60ab9be777cf1520e19582d01ebb465e82a1))

## [2.16.0] - 2026-05-22

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.15.1..v2.16.0)

### Features

- Move from npm to pnpm ([`f526a3d`](https://git.sr.ht/~mtmn/corpus/commit/f526a3d8f08ba9166c5b2df29720b8c32dbac681))

### Housekeeping

- Remove `nix-fake-hash` script ([`a6c7da2`](https://git.sr.ht/~mtmn/corpus/commit/a6c7da287002c44eadd1fc9f30d80dfe7406cb3d))
- Update release script to ues pnpm ([`1d8c099`](https://git.sr.ht/~mtmn/corpus/commit/1d8c099df52af61fc6a7b9faaca6fe84d7f61ac4))
- Remove package-lock.json ([`5c41c0a`](https://git.sr.ht/~mtmn/corpus/commit/5c41c0a1ce7cb55e13271a5f92ef7b4a22e27166))
- Release v2.16.0 ([`c89de13`](https://git.sr.ht/~mtmn/corpus/commit/c89de13482a083ebe31f221842658113b2caf7ed))

## [2.15.1] - 2026-05-21

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.15.0..v2.15.1)

### Bug Fixes

- Remove deprecated package ([`ad9f27a`](https://git.sr.ht/~mtmn/corpus/commit/ad9f27adbe022c927aba0c0481065ad10b30dccd))

### Housekeeping

- Release v2.15.1 ([`78e0e4d`](https://git.sr.ht/~mtmn/corpus/commit/78e0e4dbcf0fb5b745245ae88411633b80193f6e))

## [2.15.0] - 2026-05-15

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.14.4..v2.15.0)

### Features

- Update duckdb to 1.5.2, use node-api package ([`91b154c`](https://git.sr.ht/~mtmn/corpus/commit/91b154c47086059af4a447055925429f2e376210))

### Housekeeping

- Release v2.15.0 ([`5074136`](https://git.sr.ht/~mtmn/corpus/commit/5074136d548b75777f62f4a471f757320b263f96))

## [2.14.4] - 2026-05-15

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.14.3..v2.14.4)

### Bug Fixes

- Remove redundant packages ([`d1a5d5d`](https://git.sr.ht/~mtmn/corpus/commit/d1a5d5d70a8a3e03404953d78b798db64991fc47))

### Housekeeping

- Release v2.14.4 ([`7a5d347`](https://git.sr.ht/~mtmn/corpus/commit/7a5d347cb477f16c7d38d058e98d7799556eb28a))

## [2.14.3] - 2026-05-13

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.14.2..v2.14.3)

### Bug Fixes

- **ci:** Run npm install on release ([`6a7d64a`](https://git.sr.ht/~mtmn/corpus/commit/6a7d64a711c300f1a7436fd5eb413f093316a65c))

### Housekeeping

- Release v2.14.3 ([`8da4314`](https://git.sr.ht/~mtmn/corpus/commit/8da4314651f372e4df6dc795920f923efbe1618a))

## [2.14.2] - 2026-05-10

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.14.1..v2.14.2)

### Housekeeping

- **deps:** Bump purescript registry ([`2139557`](https://git.sr.ht/~mtmn/corpus/commit/21395573964bfe20f2f5adcb151213be686e59be))
- Release v2.14.2 ([`62eb871`](https://git.sr.ht/~mtmn/corpus/commit/62eb8719333225ced9b5f1c772b1f5a3235bab2e))

## [2.14.1] - 2026-05-08

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.14.0..v2.14.1)

### Bug Fixes

- Transparent diagram ([`c41ec83`](https://git.sr.ht/~mtmn/corpus/commit/c41ec8312ac515dfff963b67b971593fcde0ad4a))

### Housekeeping

- Release v2.14.1 ([`f940cbf`](https://git.sr.ht/~mtmn/corpus/commit/f940cbf10297ce8caacd4b2dce47ba7f1e589560))

## [2.14.0] - 2026-05-08

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.13.1..v2.14.0)

### Features

- Render diagram using graphviz ([`3a6752f`](https://git.sr.ht/~mtmn/corpus/commit/3a6752fda8ba988767efb16bb4da4b8130d2304a))

### Housekeeping

- Release v2.14.0 ([`9c83cab`](https://git.sr.ht/~mtmn/corpus/commit/9c83cab2b0fff9e5190336215ce7a05094def242))

## [2.13.1] - 2026-05-07

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.13.0..v2.13.1)

### Housekeeping

- Update readme ([`0434e69`](https://git.sr.ht/~mtmn/corpus/commit/0434e6940eb9914d8c8ce1c3aacdc285822e2860))
- Migrate prek cfg to prek.toml ([`b9dac58`](https://git.sr.ht/~mtmn/corpus/commit/b9dac5800c75279dd289a6c524de73ac851de4cf))
- **deps:** Bump versions ([`efa7176`](https://git.sr.ht/~mtmn/corpus/commit/efa71760da7427fec0560fa12a23d9883cf5f46c))
- Update git-cliff config ([`440bd8a`](https://git.sr.ht/~mtmn/corpus/commit/440bd8aa2a6f247549a056285486bd0bd286edd0))
- Rename git-release to release ([`a2fae24`](https://git.sr.ht/~mtmn/corpus/commit/a2fae2409be5a6b6121eb88d7a1bf219f3c1fc24))
- Add nix to changelog, remove trailing lines ([`63ca30f`](https://git.sr.ht/~mtmn/corpus/commit/63ca30f8b2904d17cc55cfa145fe4ab3e8e7c0d3))
- Skip pre-commit hooks when releasing ([`a29d830`](https://git.sr.ht/~mtmn/corpus/commit/a29d83001a963453a9c6c9839c1858487b91a393))
- Update purescript-registry ([`3929bd6`](https://git.sr.ht/~mtmn/corpus/commit/3929bd63460d3d6e736a37edd12b56674bd1ec71))
- Release v2.13.1 ([`4dd8389`](https://git.sr.ht/~mtmn/corpus/commit/4dd83890e47eebd7b85f69d1a70acff71a4d24d2))

## [2.13.0] - 2026-05-02

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.12.0..v2.13.0)

### Bug Fixes

- Cleanup components ([`27b63ac`](https://git.sr.ht/~mtmn/corpus/commit/27b63acb8451c70fcf9084ac5bc0cc1e79945672))
- Remove build ([`8fb6618`](https://git.sr.ht/~mtmn/corpus/commit/8fb661891ab4fd4a669d0af97ab150ab333050db))

### Features

- Change ua links to sourcehut ([`f57780c`](https://git.sr.ht/~mtmn/corpus/commit/f57780c0c47216a82c5940b267eb166b9cd4e060))

### Housekeeping

- Release v2.13.0 ([`93b4067`](https://git.sr.ht/~mtmn/corpus/commit/93b4067be293354834c6f253115d00d52ace22b6))

## [2.12.0] - 2026-05-02

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.11.0..v2.12.0)

### Features

- **ci:** Add build job ([`7963a79`](https://git.sr.ht/~mtmn/corpus/commit/7963a795a8cb0eb5ad63e3540fa0d39d47e53816))

### Housekeeping

- Release v2.12.0 ([`01085bf`](https://git.sr.ht/~mtmn/corpus/commit/01085bfda2462360a0846cb18d4f78621a1f755f))

## [2.11.0] - 2026-05-02

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.10.0..v2.11.0)

### Bug Fixes

- **ci:** Run tests on each commit ([`1c9b160`](https://git.sr.ht/~mtmn/corpus/commit/1c9b1602865c2c33487625342965fafb0c7a71d5))
- **ci:** Typo in test workflow ([`7de83e3`](https://git.sr.ht/~mtmn/corpus/commit/7de83e3ef898b3f82aa9b476812f51c39d7dc702))
- Add permissions to release-please ([`357b8e7`](https://git.sr.ht/~mtmn/corpus/commit/357b8e7bb6378f2f1b9359148316997cdab06bea))
- Manual bump version ([`165aed2`](https://git.sr.ht/~mtmn/corpus/commit/165aed2c24d76472a2a9a6396df397ec5cc19f4e))
- Typo in just recipe ([`8ea50bc`](https://git.sr.ht/~mtmn/corpus/commit/8ea50bc75e18ca297cceae47bf66a1c8a955f96b))
- Release script ([`8817d31`](https://git.sr.ht/~mtmn/corpus/commit/8817d31c8c53fe9c70f47f383d52670f8dcc94ff))

### Features

- **ci:** Update workflows ([`0cccee3`](https://git.sr.ht/~mtmn/corpus/commit/0cccee309076e29470f370e2268750f6c0e092df))
- Update deps, add `avar` ([`0f42152`](https://git.sr.ht/~mtmn/corpus/commit/0f42152c83db4bcea1968ca11d44839526fdc0cd))
- **ci:** Add git-cliff ([`78575bf`](https://git.sr.ht/~mtmn/corpus/commit/78575bf44d136638156eb188890834543c237c38))

### Housekeeping

- **ci:** Run yamlfmt on workflows ([`5bb8bf1`](https://git.sr.ht/~mtmn/corpus/commit/5bb8bf128cbc9765fdd2a840b0d33bf5849013d3))
- Remove `flake-utils` dependency ([`48ed620`](https://git.sr.ht/~mtmn/corpus/commit/48ed620d52f0b827c3b9f437858475c00e181d88))
- **master:** Release 2.11.0 ([`c35cf06`](https://git.sr.ht/~mtmn/corpus/commit/c35cf0646989aee0dda0c3f96d8f715310ee17a0))
- Update npmDepsHash ([`8e432d1`](https://git.sr.ht/~mtmn/corpus/commit/8e432d1bdab8fc7f171e46d8183f0d242237cda3))
- Remove github workflows ([`52d0dca`](https://git.sr.ht/~mtmn/corpus/commit/52d0dcafc79b03d9034d54f555d4e7f7bf2a1907))
- Update changelog ([`9143b3c`](https://git.sr.ht/~mtmn/corpus/commit/9143b3c9bcccab1a49fbfd0cd7118a621914d84c))
- Release v2.11.0 ([`3b2a13f`](https://git.sr.ht/~mtmn/corpus/commit/3b2a13f13ac1d64a040c575899f23f3a6e4e8629))

## [2.10.0] - 2026-05-01

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.9.1..v2.10.0)

### Bug Fixes

- **nix:** Rewrite build assets filtering ([`27aa762`](https://git.sr.ht/~mtmn/corpus/commit/27aa762e67154fa5937330d931fd70a914ea53fd))
- **ci:** Run tests on automated PRs ([`2c48d72`](https://git.sr.ht/~mtmn/corpus/commit/2c48d724085260f3b684850691ddd9ff330c4272))
- **ci:** Run tests from release-please pipeline ([`a715068`](https://git.sr.ht/~mtmn/corpus/commit/a7150680598509a1cc510a9da51924e5b36d09e8))

### Features

- **nix:** Integrate elm2nix ([`ea29c4d`](https://git.sr.ht/~mtmn/corpus/commit/ea29c4d0f0037d49b5534d2ec0782d1c156687be))

### Housekeeping

- **master:** Release 2.10.0 ([`2513efb`](https://git.sr.ht/~mtmn/corpus/commit/2513efb27e98ccae5b1c581f4fee7b143882a877))
- Update npmDepsHash ([`1d056ce`](https://git.sr.ht/~mtmn/corpus/commit/1d056cedb4dba8c87a97eb1045d025466565a3b6))

## [2.9.1] - 2026-04-30

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.9.0..v2.9.1)

### Bug Fixes

- Still need that hash workflow, whoops ([`3d4ee88`](https://git.sr.ht/~mtmn/corpus/commit/3d4ee887ba923537e7ffea5fbaf6b4daa983ed4d))

### Housekeeping

- **master:** Release 2.9.1 ([`28ecf5e`](https://git.sr.ht/~mtmn/corpus/commit/28ecf5e80cb9eae4660e46c509f461b27a7ce35a))
- Update npmDepsHash ([`5e68052`](https://git.sr.ht/~mtmn/corpus/commit/5e68052886ac5e560bca13200d28dc39b247ae53))

## [2.9.0] - 2026-04-30

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.8.3..v2.9.0)

### Features

- Ensure that the builds are deterministic ([`7863ebb`](https://git.sr.ht/~mtmn/corpus/commit/7863ebb170481342f0c267c89717944eb02fce87))

### Housekeeping

- Stop tripping over nix hash changes ([`2b85aa2`](https://git.sr.ht/~mtmn/corpus/commit/2b85aa227b2a8f68fec29103923634c62a0ea079))
- Add license ([`c80b111`](https://git.sr.ht/~mtmn/corpus/commit/c80b111cffd5edfeb6a26db5bfad06d948d5be84))
- **master:** Release 2.9.0 ([`977520e`](https://git.sr.ht/~mtmn/corpus/commit/977520edb95c776ec1f5cf1900e3e202dd5fff8d))

## [2.8.3] - 2026-04-25

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.8.2..v2.8.3)

### Bug Fixes

- Deprecate dhall-to-json ([`b0cf508`](https://git.sr.ht/~mtmn/corpus/commit/b0cf508390fe81605b7c1944a14a135742c92217))
- Correct release-please after history rewrite ([`9449944`](https://git.sr.ht/~mtmn/corpus/commit/944994467a8c3198aeb7818a7d220fe88d9fd6f2))
- Unbork release-please, please ([`a2e6545`](https://git.sr.ht/~mtmn/corpus/commit/a2e6545961e7f141ed4aa9519e84e1562f6447f0))
- Remove corpus component from release-please config ([`006dcb1`](https://git.sr.ht/~mtmn/corpus/commit/006dcb1739dbd7bd538733ae91a8d7d84e08e71d))
- Retrigger release-please ([`5c25025`](https://git.sr.ht/~mtmn/corpus/commit/5c2502594c69e06ee1abc0118ed6f45fe01e1324))
- Please relase ([`2e6c34a`](https://git.sr.ht/~mtmn/corpus/commit/2e6c34a0a22a76bdd6c910f52ab9936af6379cfb))

### Housekeeping

- Update npmDepsHash ([`cf11301`](https://git.sr.ht/~mtmn/corpus/commit/cf113016fa06d8165400a09e8b20e81efac5d2c8))
- Bump flake outputHash ([`8ad2d0e`](https://git.sr.ht/~mtmn/corpus/commit/8ad2d0ef8000b3b0888ba61ff0df00e69ee9d00f))
- **master:** Release 2.8.3 ([`11b0e80`](https://git.sr.ht/~mtmn/corpus/commit/11b0e809d4564fa97c4d8278be49e64cb9e90dcb))
- Update npmDepsHash ([`542dc35`](https://git.sr.ht/~mtmn/corpus/commit/542dc35c4332134acd55d7ad45fb2bd0a0296b48))

## [2.8.2] - 2026-04-25

[compare](https://git.sr.ht/~mtmn/corpus/log/v2.8.1..v2.8.2)

### Bug Fixes

- Move user to config, click listens go home ([`e07c9c8`](https://git.sr.ht/~mtmn/corpus/commit/e07c9c839b8d13395caa9dd4cb3b98d94a7a7159))
- Open cover on click, genre tag css ([`096e7ad`](https://git.sr.ht/~mtmn/corpus/commit/096e7ad5ffa73313e5695abc320a2eda81310ac4))
- Yeild request when duckdb connection is present ([`4c423ee`](https://git.sr.ht/~mtmn/corpus/commit/4c423ee4dc265ea073580c663d8c664d9d6337df))
- Flaky tests, ignore results ([`446af57`](https://git.sr.ht/~mtmn/corpus/commit/446af57b053534e856ca0438165f7c3de69339fe))
- Use native ps for url handling ([`f0f178f`](https://git.sr.ht/~mtmn/corpus/commit/f0f178fe2a469da869cfbd28997f51491a05c2dd))
- Get rid of regex interop functions ([`3896037`](https://git.sr.ht/~mtmn/corpus/commit/3896037a5b404bb30eaa39e8fd9fa89cf5cbd717))
- Update nix hashes ([`d58489b`](https://git.sr.ht/~mtmn/corpus/commit/d58489b29506923144e34b634541427f8dbcc3c2))
- **elm:** Expose only necessary html tags ([`acfd25b`](https://git.sr.ht/~mtmn/corpus/commit/acfd25b0733120db7e67f7020f2c74e80945badf))
- **elm:** Expose only necessary html tags ([`5ef660d`](https://git.sr.ht/~mtmn/corpus/commit/5ef660db7ed2f392b1ae0f384725b1bf6f92698a))
- Default database path to cwd ([`6cc7ece`](https://git.sr.ht/~mtmn/corpus/commit/6cc7ece69ae971a86ddcd29c04816801a3d25ff2))
- Instrument complete HTTP span ([`c6f7605`](https://git.sr.ht/~mtmn/corpus/commit/c6f7605678876dde19878e5bcd85a2001405eb79))
- Dont block startUser on sync ([`6d5a660`](https://git.sr.ht/~mtmn/corpus/commit/6d5a660bc17c4bb57bbf8f5289ac010514c5fe22))
- Optimize client.js output ([`1bec5be`](https://git.sr.ht/~mtmn/corpus/commit/1bec5be07224d26f8e0c478aa33dd7ccf263846a))
- Update docs; add metrics switch, fixes ([`8008ede`](https://git.sr.ht/~mtmn/corpus/commit/8008ede24ab1dde56c14ed552d91babc7a473269))
- Sanitize duckdb queries ([`280b211`](https://git.sr.ht/~mtmn/corpus/commit/280b2115ca846ac7246e33387160da68eb867c91))
- Move template to a separate file ([`aae7ecf`](https://git.sr.ht/~mtmn/corpus/commit/aae7ecf2c535ac4b483bda061f83962272677152))
- Sanitize log output; remove cors ([`a40739b`](https://git.sr.ht/~mtmn/corpus/commit/a40739b33c11b873bd87b9ef8277a5355e8649e7))
- Add build step, leaky queries ([`52db1af`](https://git.sr.ht/~mtmn/corpus/commit/52db1afe988e9d230603fe5f8bc4b28c48a089ce))
- Gha backoff on error ([`d597f95`](https://git.sr.ht/~mtmn/corpus/commit/d597f956596a4c1ff9cd752c688289d546d09339))
- Update tests ([`651191b`](https://git.sr.ht/~mtmn/corpus/commit/651191b8f202b0e6670de53012782c5e1312a000))
- InitialSync halts syncing, broken range query ([`99e8028`](https://git.sr.ht/~mtmn/corpus/commit/99e802804943177b0110926601096350e82903a3))
- Make css less whimsical, i think ([`e19fa83`](https://git.sr.ht/~mtmn/corpus/commit/e19fa830116ed60e4c23a039d174dfbcc54d5c46))
- Add label to tests ([`a7f4e30`](https://git.sr.ht/~mtmn/corpus/commit/a7f4e30a632ad9a176b57fbfe42e603fc900dd32))
- Missing doc entries ([`86314ec`](https://git.sr.ht/~mtmn/corpus/commit/86314ecea72cf207715fd2bf568cfd39d3c6243b))
- Missing selection for track and album ([`a96810e`](https://git.sr.ht/~mtmn/corpus/commit/a96810eb4cf9a3ee74ca0c73c987b67dc8c1ed0b))
- Remove initialSync param ([`fb55c02`](https://git.sr.ht/~mtmn/corpus/commit/fb55c025ef5c09d3659de40e99cf243b12c86c98))
- Cache and convert cover art in the background ([`0fb8594`](https://git.sr.ht/~mtmn/corpus/commit/0fb859496b6ac4097930feafc8ea35858d1a72f4))
- Remove unused imports; better logging ([`4d0fb8e`](https://git.sr.ht/~mtmn/corpus/commit/4d0fb8e77a8b5ef721a2da4e41c917d668453b46))
- Run npmDepsHash job on each commit ([`5dac304`](https://git.sr.ht/~mtmn/corpus/commit/5dac304dc349fcf0399bdc709f7b68ff31615d6d))
- Revert release-please gha ([`f179336`](https://git.sr.ht/~mtmn/corpus/commit/f179336acb1a69aa88fe4a763947b45060ab130a))
- Unhandled last.fm json serialization ([`697864f`](https://git.sr.ht/~mtmn/corpus/commit/697864f57afd7be5fe324529926d373c81de3704))
- Remove unused imports ([`82bbb06`](https://git.sr.ht/~mtmn/corpus/commit/82bbb061aa0d3d4e001b1727268660f91134d29d))
- Unhandled last.fm errors ([`304c446`](https://git.sr.ht/~mtmn/corpus/commit/304c446cb01f7d37aa004bae05030534e0a3fe15))
- Wording in about ([`31a70d3`](https://git.sr.ht/~mtmn/corpus/commit/31a70d3181fe5907f5bcd2872ee1f0a0184d23ee))
- Add user-agent headers to fetchers ([`e2bed95`](https://git.sr.ht/~mtmn/corpus/commit/e2bed95fda636e26d591fd24cf4efa267e392a80))
- Count api in scrobbles metric ([`010aefa`](https://git.sr.ht/~mtmn/corpus/commit/010aefaa2d84053d95aee09a1e93d8ca1c751f3c))
- Change cover cache order to caa=>discogs=>lastfm ([`5c9797c`](https://git.sr.ht/~mtmn/corpus/commit/5c9797c1be6cdfc5698174ba3af4a7552a1ece6f))
- Add corsOrigin config option ([`3b2e9ba`](https://git.sr.ht/~mtmn/corpus/commit/3b2e9bae48972f9f815fa7a4ba2dfe672833efd5))
- Add user management recipes, exit properly ([`6c03e49`](https://git.sr.ht/~mtmn/corpus/commit/6c03e49dfaebd004ea832be7f65709e847a37251))

### Documentation

- Readme ([`030a32b`](https://git.sr.ht/~mtmn/corpus/commit/030a32b4d7a9bd7b8fee3367d3a1d92daeb5dd98))
- Add and reference docs, just usage ([`2cc4891`](https://git.sr.ht/~mtmn/corpus/commit/2cc4891e3fef66a340ef4634c5a0c42b6d33d71f))
- Add duckdb_queries.md ([`a0417c2`](https://git.sr.ht/~mtmn/corpus/commit/a0417c208c8de9ce8f5f6ab69f4eaa4136b39e70))
- Typos, formatting, etc ([`b707d00`](https://git.sr.ht/~mtmn/corpus/commit/b707d00e44dc2b883b8ffb557261811b66490278))
- Add instance uri ([`53848e1`](https://git.sr.ht/~mtmn/corpus/commit/53848e114f0077155c97cc4e206f31b95a385af5))

### Features

- Fix builds, inline htmx to ps-halogen ([`e394d45`](https://git.sr.ht/~mtmn/corpus/commit/e394d45dba7c024d0a5057945d4261fe623c8048))
- Duckdb, blob storage, pagination ([`7588434`](https://git.sr.ht/~mtmn/corpus/commit/75884341e60299f61a76d0c6ca32a120db2c966a))
- **ci:** Add nix flake ([`e61bcc2`](https://git.sr.ht/~mtmn/corpus/commit/e61bcc29c919d1596585049ef9739d57793e1c94))
- Periodic scans, disable source builds, docs ([`c33abbb`](https://git.sr.ht/~mtmn/corpus/commit/c33abbbc38405f453456e1400a9bcb595d5dd30f))
- Add logging, housekeeping ([`0e601bf`](https://git.sr.ht/~mtmn/corpus/commit/0e601bfa065ffe4aa34b0cdab43b554ed76e63cf))
- Fix builds, inline htmx to ps-halogen ([`adcefbc`](https://git.sr.ht/~mtmn/corpus/commit/adcefbce1a2f0f7a6f3145cdac7cda9366656364))
- Duckdb, blob storage, pagination ([`82b4af5`](https://git.sr.ht/~mtmn/corpus/commit/82b4af5fb85a7f2275c7ea631c21eafd82302c1c))
- Deduplicate cover fetching logic ([`e65c4ad`](https://git.sr.ht/~mtmn/corpus/commit/e65c4ad68a33cf3935bd8f8915a1c9b53826aa5d))
- Add stats ([`97eeb6e`](https://git.sr.ht/~mtmn/corpus/commit/97eeb6e2e3f7a42c8618c8f53d579d4b5e15e37a))
- Zoom on hover for covers, bugfixes ([`c619230`](https://git.sr.ht/~mtmn/corpus/commit/c619230f595b49d7679f2d27636a1e4bc3383416))
- Add tag hover ([`ca89de9`](https://git.sr.ht/~mtmn/corpus/commit/ca89de9841db55e7805180efcbf2abd73ab9f3d5))
- **stats:** Add show all expander ([`a57b108`](https://git.sr.ht/~mtmn/corpus/commit/a57b108a149ea4784c8ed20c9474c65fa55972e6))
- Add tests ([`91f0021`](https://git.sr.ht/~mtmn/corpus/commit/91f00219a6799aad4ca110510503048856b705d3))
- Add more tests, update justfile ([`fa35613`](https://git.sr.ht/~mtmn/corpus/commit/fa356138b519c8de7e972e7c316eccde27ac60e9))
- Add backups, enabled params ([`cada497`](https://git.sr.ht/~mtmn/corpus/commit/cada497f6a566dc3bce7c714f58ec74cb52bc6a2))
- Add lastfm support ([`f9ae9ae`](https://git.sr.ht/~mtmn/corpus/commit/f9ae9aee4c4815d658aabc36c8e2a0cda18c35cb))
- Add tests and update readme ([`98e5070`](https://git.sr.ht/~mtmn/corpus/commit/98e5070357c38812b1c8c35a5cbc3efd51104994))
- Improve logging ([`95c2aa3`](https://git.sr.ht/~mtmn/corpus/commit/95c2aa378492977c669ba62b5ea07d6e872a2387))
- Add filters, allow show all ([`248edff`](https://git.sr.ht/~mtmn/corpus/commit/248edff954cb1d7e0f8d55b854b4426c9f24e560))
- **stats:** Add custom date range ([`abd57a1`](https://git.sr.ht/~mtmn/corpus/commit/abd57a1af78cd57e46a0361a3701728473b0c9da))
- Duckdb chepoint to a bucket ([`c30098b`](https://git.sr.ht/~mtmn/corpus/commit/c30098bccb7d0e7ba0a8b67a7577e9ca1d863058))
- Use elm in frontend instead of halogen ([`9545793`](https://git.sr.ht/~mtmn/corpus/commit/9545793c8ad0f7333c5205293a4488cfa9333104))
- Use elm in frontend instead of halogen ([`6833d81`](https://git.sr.ht/~mtmn/corpus/commit/6833d816e33b882c8fd3fac87b8167e3bab864db))
- Add support for defining users ([`92dc182`](https://git.sr.ht/~mtmn/corpus/commit/92dc18239440f6858d4bf26321f4573b92ebfab2))
- Add write locks to db ([`e1cefba`](https://git.sr.ht/~mtmn/corpus/commit/e1cefbaee28bae5d3a22745dd10606686269c84b))
- Add metrics endpoint ([`429576a`](https://git.sr.ht/~mtmn/corpus/commit/429576a8a41a113c51c77cae83ceedba9d520520))
- Add otel tracing ([`8cd250e`](https://git.sr.ht/~mtmn/corpus/commit/8cd250e8f8fa3ac23b28ab960a7e30c0614a62d6))
- Rewrite into folds, cover/genre rewrite ([`9463878`](https://git.sr.ht/~mtmn/corpus/commit/94638781984174cf89e256ee853c2c914c0deb89))
- Integrate cosine.club api ([`f6eb784`](https://git.sr.ht/~mtmn/corpus/commit/f6eb784a07b93f64d8a24d7df713fe08b2045593))
- **breaking:** Remove otel, add cosine.club metrics ([`06522c9`](https://git.sr.ht/~mtmn/corpus/commit/06522c9ec707bc36a8d393f6a1bf7422818d47e2))
- Add grafana dashboard ([`762e5ae`](https://git.sr.ht/~mtmn/corpus/commit/762e5ae8062d90dd175601cb44e9f6321dda1fd8))
- Change user slug, fixes ([`35059ee`](https://git.sr.ht/~mtmn/corpus/commit/35059ee5306d419b0632ea23699aee9319704ac0))
- Add about section ([`f055cbd`](https://git.sr.ht/~mtmn/corpus/commit/f055cbd9767fe690d2351bac8a2c794e4164aac0))
- Add search to listens section ([`6b99cb9`](https://git.sr.ht/~mtmn/corpus/commit/6b99cb9e58cdf50b7a03a51f49a8e42b117d97af))
- Add about, labels and fix search ([`346b4d5`](https://git.sr.ht/~mtmn/corpus/commit/346b4d5fc7425664c82be8e496dfafb4d9437cdc))
- Add custom user name, fixes ([`0105eee`](https://git.sr.ht/~mtmn/corpus/commit/0105eee664727795aee703fde3095b58e3e84de0))
- Shutdown handling, fix race conditions ([`0e6c154`](https://git.sr.ht/~mtmn/corpus/commit/0e6c1544957a348a76cb2e81533d7d7c33e98b18))
- Scrobbles searchable by album ([`7803007`](https://git.sr.ht/~mtmn/corpus/commit/7803007814b224bdac9a6cfacf2ef5f09e1a1827))
- Shutdown handling, fix race conditions ([`9632dc5`](https://git.sr.ht/~mtmn/corpus/commit/9632dc517e3d488c3aa83c21068110a8e6f76cf6))
- Add track filter and make all filters clickable ([`b57a3ce`](https://git.sr.ht/~mtmn/corpus/commit/b57a3ce797f4558a3bc49fee92e37c67156f6bbf))
- Update user agents with github repo ([`1dbde20`](https://git.sr.ht/~mtmn/corpus/commit/1dbde20e2804fa04fe80d9b467d10c06e14fb5b2))
- Match colors to doric-obsidian ([`ab11a25`](https://git.sr.ht/~mtmn/corpus/commit/ab11a2563dde7e877af99074e0a66debbaa6819c))
- Convert to avif; decouple Client.elm ([`d01bb0b`](https://git.sr.ht/~mtmn/corpus/commit/d01bb0b28dc69f2eac9d7733fdd7002575b6e420))
- Doucple Main.purs to modules ([`93f2e0d`](https://git.sr.ht/~mtmn/corpus/commit/93f2e0d5acafce95f29d0a75420c3a99c4e3b55e))
- Move scrobbling logic to Sync.purs ([`4f8d8de`](https://git.sr.ht/~mtmn/corpus/commit/4f8d8de9bf105a38012de25068364b80cb075582))
- Download large front covers from caa ([`2e8d268`](https://git.sr.ht/~mtmn/corpus/commit/2e8d268a16effb772794cdc6bace2e5b8968b41b))
- Try various cover art sizes ([`8b8811d`](https://git.sr.ht/~mtmn/corpus/commit/8b8811d7e2c0cf6fe4e57880ef8d0b82470a7563))
- Simplify cover sources logic ([`0a06102`](https://git.sr.ht/~mtmn/corpus/commit/0a06102a2d7d2f073e02b9be0945f7725f1076cb))
- Lookup release json from caa before fetch ([`b59bc2f`](https://git.sr.ht/~mtmn/corpus/commit/b59bc2ffe60e1fa8bd797209af5dd3ebcafd74f7))
- Add listenbrainz-like endpoint ([`feafab2`](https://git.sr.ht/~mtmn/corpus/commit/feafab2a8a43f51acf1f85573800a1a8b6d94c15))
- Hash user token ([`71c9ff7`](https://git.sr.ht/~mtmn/corpus/commit/71c9ff7b254bff94b0d4db7237ea0cf88b00cbc0))
- Add docs for submission endpoint ([`81d101a`](https://git.sr.ht/~mtmn/corpus/commit/81d101a0dd916cdeed3664734be04a7789e0d63c))
- Add tests for endpoint ([`999c811`](https://git.sr.ht/~mtmn/corpus/commit/999c811e963a498ef34c4b4b0840ed17a3b8db87))
- Add user mgmt commands ([`a19c9b4`](https://git.sr.ht/~mtmn/corpus/commit/a19c9b4436674bec22a1b55d9b83fed150072e84))
- Deprecate .dhall users file, fmt ([`9eadd11`](https://git.sr.ht/~mtmn/corpus/commit/9eadd119054a9e65b0ce6053fc2e386f5fdb2f9b))

### Housekeeping

- Add gitignore ([`db67d60`](https://git.sr.ht/~mtmn/corpus/commit/db67d60f9d5278957dde85a2cb078dc7c573eb36))
- Fiddling with builds, naming ([`31c8243`](https://git.sr.ht/~mtmn/corpus/commit/31c8243c27a5c3093a8fb1192b50b3ae011a740d))
- Remove node-sqlite3 dependency ([`9dfaa89`](https://git.sr.ht/~mtmn/corpus/commit/9dfaa892efce32fd26b4da883cb602b05d547dad))
- Fiddling with builds, naming ([`40b1bdf`](https://git.sr.ht/~mtmn/corpus/commit/40b1bdf011002dfbd91b13e88adfb97c28efa513))
- Fix nix, logging, fmt ([`047be2f`](https://git.sr.ht/~mtmn/corpus/commit/047be2f0eb8b5160dc8984f1b9492074a859d3bb))
- Cleanup, builds ([`f1dfd5b`](https://git.sr.ht/~mtmn/corpus/commit/f1dfd5bfb4ff9ad745980ee11232dbeb54ba3633))
- Add favicon ([`512443c`](https://git.sr.ht/~mtmn/corpus/commit/512443c84e5ccd144230a3144052bd93d09f5afe))
- Add binary cache ([`58cec8b`](https://git.sr.ht/~mtmn/corpus/commit/58cec8be9943c35f2a33e50d1d2fdb23ba1875d0))
- Making builds work ([`cdfe276`](https://git.sr.ht/~mtmn/corpus/commit/cdfe2766168c3942aa8abbf906dbdf4f989badb7))
- Typo ([`28b040e`](https://git.sr.ht/~mtmn/corpus/commit/28b040e16e8438368723dd6a8aeac5457317aee9))
- Add /healthz endpoint ([`c47e7de`](https://git.sr.ht/~mtmn/corpus/commit/c47e7de4582aaed2442c40ff7a6c05e655fcde7e))
- Add footer, update readme, tidy ([`978298d`](https://git.sr.ht/~mtmn/corpus/commit/978298d616a5c72ef42e0ca57522ca83a23aab7c))
- Update example dotenv, add to nix env ([`738a007`](https://git.sr.ht/~mtmn/corpus/commit/738a007143d436437d108e93b2aa1d6b5623917d))
- Update docs and justfile ([`fbf0143`](https://git.sr.ht/~mtmn/corpus/commit/fbf0143888d418d809dc034a502eb71e744d60df))
- Fix nix build, remove dangling deps ([`aa1906e`](https://git.sr.ht/~mtmn/corpus/commit/aa1906e73cdfeae6177d54f357ad9a7a34dd1e97))
- Fix nix builds ([`17ef69c`](https://git.sr.ht/~mtmn/corpus/commit/17ef69c19d08d6737d492833ec49b99ddb6b7cd4))
- Add favicon ([`d2a0549`](https://git.sr.ht/~mtmn/corpus/commit/d2a0549aa298bc4366264e6ba2e5bf6b11d37c23))
- Add devenv and cachix ([`8a2ffb5`](https://git.sr.ht/~mtmn/corpus/commit/8a2ffb58b5cd338c373c626d7fde0def8501ba77))
- Install pre-commit hooks ([`c3ca613`](https://git.sr.ht/~mtmn/corpus/commit/c3ca613d0131185e4a661a388323cf5ce045e050))
- Run biome on src/ and test/ ([`b719cd5`](https://git.sr.ht/~mtmn/corpus/commit/b719cd5c618c34c5081095831f3f2a75e81d4098))
- System flow fixes ([`0573219`](https://git.sr.ht/~mtmn/corpus/commit/05732197d5a128b088863b4d7a6d57195278dc30))
- Update custom binary cache ([`5e8ea1b`](https://git.sr.ht/~mtmn/corpus/commit/5e8ea1b40bf52fb2d43a8b651454d1f9795c38ff))
- Rename to corpus ([`db138cf`](https://git.sr.ht/~mtmn/corpus/commit/db138cf32d94d0f814bb755e004484ee90f06174))
- Rename to corpus ([`709e797`](https://git.sr.ht/~mtmn/corpus/commit/709e79732448b73df60384f3cc765cb8d3d65a64))
- Remove custom binary cache ([`d9bf40b`](https://git.sr.ht/~mtmn/corpus/commit/d9bf40b8520765507c4c60d32717b22315c5f75a))
- Cleanup ([`14fa6fe`](https://git.sr.ht/~mtmn/corpus/commit/14fa6fef846e74b2eb12a3a5ba2a3e98c2f85f6a))
- Remove containerfile ([`bf90a88`](https://git.sr.ht/~mtmn/corpus/commit/bf90a88810bdfd34f90bf86ebd55823f8ffa1fa3))
- Remove containerfile ([`738ec19`](https://git.sr.ht/~mtmn/corpus/commit/738ec194665b4cb0a9ae6e30d5ed16f2a5cd4275))
- Update docs ([`63d4460`](https://git.sr.ht/~mtmn/corpus/commit/63d4460d28f3fc063102a38d575b282a45a6b1f9))
- Update readme ([`4c106be`](https://git.sr.ht/~mtmn/corpus/commit/4c106be4c248eb210665588b13d958b506cb9f0a))
- Rename users config environment variable ([`92ffec1`](https://git.sr.ht/~mtmn/corpus/commit/92ffec13f93b0f4ac52fd89b3c474b005b7c29c3))
- Remove update timestamp from footer ([`0666d4f`](https://git.sr.ht/~mtmn/corpus/commit/0666d4fb772b2e4d1fee48fa786a74db605e735e))
- Add dev just recipe, cleanup users.dhall ([`5ee993e`](https://git.sr.ht/~mtmn/corpus/commit/5ee993e1b5a2e6bc343d30d88b47022361d00b68))
- Update flake hash ([`057c57a`](https://git.sr.ht/~mtmn/corpus/commit/057c57a2248f06e2de041fe028701318e616a271))
- Add purs-backend-es lib ([`c004ec3`](https://git.sr.ht/~mtmn/corpus/commit/c004ec32133da069ac9da7ab78da7bf88ea2b2e7))
- Add access logs ([`95053ec`](https://git.sr.ht/~mtmn/corpus/commit/95053ec72011d16c922192e687ae5445e80260a1))
- Bump npm deps hash ([`bf29101`](https://git.sr.ht/~mtmn/corpus/commit/bf2910189341ad9d4e35b94ea400d530ece5d115))
- Add missing env vars to readme ([`69b5c0c`](https://git.sr.ht/~mtmn/corpus/commit/69b5c0cabb9dd07c86d3d700cfbb7c824a630b31))
- Update readme ([`e05206f`](https://git.sr.ht/~mtmn/corpus/commit/e05206f4d552869ae52b1e98cff8affc8b7a2426))
- Bump version ([`0217d14`](https://git.sr.ht/~mtmn/corpus/commit/0217d144f4eedc7886dd6c2248eddc81170fd44e))
- Bump version ([`5650456`](https://git.sr.ht/~mtmn/corpus/commit/5650456a2446e68023eef7cef50aace64c4f4df3))
- Add release-please pipeline ([`9e974d4`](https://git.sr.ht/~mtmn/corpus/commit/9e974d4ffcef08794c6cd9066114b37dd9bf9bf6))
- **master:** Release 1.1.1 ([`03b5b27`](https://git.sr.ht/~mtmn/corpus/commit/03b5b27f31aaab33980ed75ad8e0e2945b2dafad))
- Update npmDepsHash ([`00639ce`](https://git.sr.ht/~mtmn/corpus/commit/00639ce3e32f428229513fa5da0666862c4987ba))
- Update docs ([`a348e61`](https://git.sr.ht/~mtmn/corpus/commit/a348e61601bda61181ab34c5a07142b593f25173))
- **master:** Release 1.2.0 ([`afdf230`](https://git.sr.ht/~mtmn/corpus/commit/afdf230e546cb0241476da42514f426a44618767))
- Update npmDepsHash ([`bdacf8e`](https://git.sr.ht/~mtmn/corpus/commit/bdacf8effe9b69cd333a10e8a5a59b883ea15198))
- Add whine (linter) ([`e0b2708`](https://git.sr.ht/~mtmn/corpus/commit/e0b2708337cc3ef8f418dc3f2098ee13fd133ba1))
- Linter fixes ([`ac54052`](https://git.sr.ht/~mtmn/corpus/commit/ac540524df7d2b50eac6ba64abd1943ebff6ed3c))
- Add tests ([`60f391f`](https://git.sr.ht/~mtmn/corpus/commit/60f391feab7ec65bb942b0d13edcd7c8a7a38d19))
- Pin versions; init pinact ([`69bd019`](https://git.sr.ht/~mtmn/corpus/commit/69bd019f0f97968e31b470a4634fb9ac4459352a))
- **master:** Release 1.3.0 ([`4065e4b`](https://git.sr.ht/~mtmn/corpus/commit/4065e4be6622aaf7c6fb7b54a7d87c8837b340f7))
- Update npmDepsHash ([`afb05b0`](https://git.sr.ht/~mtmn/corpus/commit/afb05b059aaf926828c9b27cc7d334ae71999e6d))
- **master:** Release 1.3.1 ([`f3f26ab`](https://git.sr.ht/~mtmn/corpus/commit/f3f26ab458f1ee147a407a7f1f36f1619bd89be6))
- Update npmDepsHash ([`c39d3f1`](https://git.sr.ht/~mtmn/corpus/commit/c39d3f1aac6c535cd445e99ca78a43cbbdef85ee))
- **master:** Release 1.4.0 ([`d39639f`](https://git.sr.ht/~mtmn/corpus/commit/d39639f72d8e4f42da9fcc1b0149cda8ee7c6476))
- Update npmDepsHash ([`604aec6`](https://git.sr.ht/~mtmn/corpus/commit/604aec6349fab29290e157b08dd675671fec5468))
- **master:** Release 2.0.0 ([`cd2a354`](https://git.sr.ht/~mtmn/corpus/commit/cd2a354a19c54a75071273baf40bb3f9f4112070))
- Update npmDepsHash ([`83db397`](https://git.sr.ht/~mtmn/corpus/commit/83db39782470bc822bde217ab5f4e8687943b342))
- **master:** Release 2.1.0 ([`9c02d52`](https://git.sr.ht/~mtmn/corpus/commit/9c02d5293871223da90dece5cdc28b5a965fb439))
- Update npmDepsHash ([`9f54422`](https://git.sr.ht/~mtmn/corpus/commit/9f54422364a7e9ef100c22946a98089f059c0504))
- Update readme ([`61538d6`](https://git.sr.ht/~mtmn/corpus/commit/61538d62c27818f50242e854d72135ae67cf5e6c))
- Add cosine.club to docs ([`f6b3917`](https://git.sr.ht/~mtmn/corpus/commit/f6b391770ecbd9f8b3ef3608df6f14f8708f485a))
- **master:** Release 2.1.1 ([`7d364aa`](https://git.sr.ht/~mtmn/corpus/commit/7d364aa04872c66b780b86facc771b0a23561da7))
- Update npmDepsHash ([`efcc94f`](https://git.sr.ht/~mtmn/corpus/commit/efcc94f92296803b08e5f85a92746a047d5c82fb))
- Add dhall to json recipe ([`b979cc5`](https://git.sr.ht/~mtmn/corpus/commit/b979cc51ba34921de5e169edd453ea5bcd7f825b))
- Update links ([`be7ddb4`](https://git.sr.ht/~mtmn/corpus/commit/be7ddb4f3b074eecd1107cfca3c6adfcbb7b6c1f))
- Add elm-analyse to check recipe ([`5b39e9c`](https://git.sr.ht/~mtmn/corpus/commit/5b39e9c30e9cbc3618aed559857190b3531c3ef7))
- Add whine to check recipe ([`c456c17`](https://git.sr.ht/~mtmn/corpus/commit/c456c17f2b09f765c4f9b6085f2593d56e209d7d))
- **master:** Release 2.2.0 ([`1ba702e`](https://git.sr.ht/~mtmn/corpus/commit/1ba702e7096b30787147734d376b128b31fa6ca9))
- Update npmDepsHash ([`1d6fdcd`](https://git.sr.ht/~mtmn/corpus/commit/1d6fdcd3b19171ea2c3f79014920e09b2829adf0))
- **nix:** Incorrect npm hash ([`0f90580`](https://git.sr.ht/~mtmn/corpus/commit/0f9058098329f7cb3106cfe00e15dbf0aa54ead3))
- Update users.dhall ([`bf79784`](https://git.sr.ht/~mtmn/corpus/commit/bf79784a0508c459077701c5d4e860cf7fe12828))
- **elm:** Wording in about section ([`d4a0fee`](https://git.sr.ht/~mtmn/corpus/commit/d4a0feea18c1a5a0fa860a88e5544b0c968ed84a))
- Increase backup frequency to 24h ([`b0fe62f`](https://git.sr.ht/~mtmn/corpus/commit/b0fe62f13b4b19b7ada111b68521cb0bf262ff98))
- Use Fn/runFn for multi-argument FFIs ([`90ac1a2`](https://git.sr.ht/~mtmn/corpus/commit/90ac1a2fba7a2fe507056ae58e919f74737df402))
- **master:** Release 2.3.0 ([`19a440f`](https://git.sr.ht/~mtmn/corpus/commit/19a440f16b8952eed135aaecbdfc9927a419359a))
- Update npmDepsHash ([`81e9c52`](https://git.sr.ht/~mtmn/corpus/commit/81e9c52d8863c6fa45247f8368ccab5c16e8ee5f))
- **master:** Release 2.3.1 ([`52c4b51`](https://git.sr.ht/~mtmn/corpus/commit/52c4b5131c71f0ff4be8f3d6a68c919fe83ff67a))
- Update npmDepsHash ([`61f5d9d`](https://git.sr.ht/~mtmn/corpus/commit/61f5d9dd067623408a9ba7e5a0445b92847c23be))
- **master:** Release 2.4.0 ([`98958c6`](https://git.sr.ht/~mtmn/corpus/commit/98958c67fd5e3c7aa2c56a16b0cccd06b69eda66))
- Update npmDepsHash ([`8838b51`](https://git.sr.ht/~mtmn/corpus/commit/8838b510a6f027519bbc488d72a87963f23bdf36))
- Update npm hash ([`3ab2cc8`](https://git.sr.ht/~mtmn/corpus/commit/3ab2cc87e80dbabb273e984b071a9f31e84a9314))
- Update npmDepsHash ([`d514a81`](https://git.sr.ht/~mtmn/corpus/commit/d514a81e8c53b11ffc2b17d233f17d036cfbf4cd))
- Fix spago hash ([`67f866d`](https://git.sr.ht/~mtmn/corpus/commit/67f866d1cdfe73d1f2e07e96caacbe7196371709))
- **master:** Release 2.5.0 ([`0d587ce`](https://git.sr.ht/~mtmn/corpus/commit/0d587ce1a39cfc7b1944b6a709c14c6c921a0c5e))
- Update npmDepsHash ([`da2a93e`](https://git.sr.ht/~mtmn/corpus/commit/da2a93e793c51247773db048790fa7a66e2850ae))
- **master:** Release 2.5.1 ([`9a4ab35`](https://git.sr.ht/~mtmn/corpus/commit/9a4ab3521df3f30d97e5839336815b5e54c3c289))
- Update npmDepsHash ([`7d8d33f`](https://git.sr.ht/~mtmn/corpus/commit/7d8d33f549c0fdf5da7c73e23627c8484f75727c))
- Add host to app config ([`a9d906a`](https://git.sr.ht/~mtmn/corpus/commit/a9d906a98b1e67de7156a93b6c5e6e9e86e3cda3))
- **master:** Release 2.6.0 ([`506805b`](https://git.sr.ht/~mtmn/corpus/commit/506805b7858021fc23d7251c2cd782d5577a037c))
- Update npmDepsHash ([`7f4bfd6`](https://git.sr.ht/~mtmn/corpus/commit/7f4bfd6cbc8c16e20d01c2b5dcedcad27e898c07))
- Add nix-fake-hash script ([`b7dac46`](https://git.sr.ht/~mtmn/corpus/commit/b7dac46c6dc28ae4ff4d7463c3aad1d63756bc54))
- Fix hashes ([`7fadcf1`](https://git.sr.ht/~mtmn/corpus/commit/7fadcf16e174044eb37a5c203ad919a8da5b5213))
- **master:** Release 2.7.0 ([`77de401`](https://git.sr.ht/~mtmn/corpus/commit/77de40145e0d211fc51ff8e00af40722d033199b))
- Update npmDepsHash ([`b74cb16`](https://git.sr.ht/~mtmn/corpus/commit/b74cb16c44790dd82fd36397d0763a17c6cdac1e))
- **master:** Release 2.7.1 ([`51d04e7`](https://git.sr.ht/~mtmn/corpus/commit/51d04e7d37823c1b82dbe2878ea7dd7f4a217d1a))
- Update npmDepsHash ([`3a0abfc`](https://git.sr.ht/~mtmn/corpus/commit/3a0abfcd483f6e70f7e928f19f7ec71384ef7aac))
- Install purescript-language-server ([`4634293`](https://git.sr.ht/~mtmn/corpus/commit/46342937d0b13c07b83b52da390a90121ea8ccff))
- **master:** Release 2.8.0 ([`e93288b`](https://git.sr.ht/~mtmn/corpus/commit/e93288b36102a76e6d7f4fbbb060612693f83220))
- Update npmDepsHash ([`41c1e65`](https://git.sr.ht/~mtmn/corpus/commit/41c1e6504d3747575e1122ecf49c5dc5ea3cfd41))
- Import reorder from lsp ([`7f228b0`](https://git.sr.ht/~mtmn/corpus/commit/7f228b0a065d9ae29ed5d29eb56ab31def25eff1))
- Remove korpus.webp ([`767f83a`](https://git.sr.ht/~mtmn/corpus/commit/767f83af87d7a23b67d8a4bb383cc61a5e32f915))
- **master:** Release 2.8.1 ([`73bbf47`](https://git.sr.ht/~mtmn/corpus/commit/73bbf47ba2789ce990f74ba123cb16e0eaf57319))
- Update npmDepsHash ([`e3548d1`](https://git.sr.ht/~mtmn/corpus/commit/e3548d12051ae434800bc97cd62baf53212403e7))
- Fix readme ([`1d03354`](https://git.sr.ht/~mtmn/corpus/commit/1d0335480168f398eab8b0845f176b5c601069d4))
- Add live instance link to repo ([`49d3f45`](https://git.sr.ht/~mtmn/corpus/commit/49d3f45d5c313c33d89e24ff58412b5348b13e9a))
- **master:** Release 2.8.2 ([`a5cfde7`](https://git.sr.ht/~mtmn/corpus/commit/a5cfde729872917e49b236b61663b4f53dabd1aa))
