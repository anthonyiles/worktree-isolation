# Changelog

## [0.10.0](https://github.com/anthonyiles/worktree-isolation/compare/v0.9.0...v0.10.0) (2026-11-11)


### ⚠ BREAKING CHANGES

* WORKTREE_DOCKER_SERVICE= no longer turns off the compose service's environment for docker-image containers; empty now means the default. Override single values with WORKTREE_DOCKER_ENV instead.

### Features

* an empty WORKTREE_DOCKER_SERVICE uses the service using the image ([a828658](https://github.com/anthonyiles/worktree-isolation/commit/a8286583816d305011f481dc2e56d8b9867e73ea))
* make the commented-out settings in .worktree-isolation.env match the defaults, so uncommenting one changes nothing ([ac09eea](https://github.com/anthonyiles/worktree-isolation/commit/ac09eea930243d864bd4aebe57ee4abe0fbc3af8))
* name worktree test databases {name}_wt_{worktree}_test, next to their development database ([73b1248](https://github.com/anthonyiles/worktree-isolation/commit/73b12486d3d5d5218934eab0e2d9a3a48b653059))
* test databases sort next to their worktree's dev database, and safe-to-uncomment config defaults ([#42](https://github.com/anthonyiles/worktree-isolation/issues/42)) ([6d37f42](https://github.com/anthonyiles/worktree-isolation/commit/6d37f424d662775aba080493b6fafc33cd0f8368))


### Bug Fixes

* keep an apostrophe out of the install config, which broke the tests on Bash 3.2 ([e237f51](https://github.com/anthonyiles/worktree-isolation/commit/e237f515b484bd61d5f0d754976126616a6fd544))
* read "KEY=   # comment" in env files as empty, not as the comment ([a272fce](https://github.com/anthonyiles/worktree-isolation/commit/a272fceda4b5656d36bb164d15ac556326f0cc74))

## [0.9.0](https://github.com/anthonyiles/worktree-isolation/compare/v0.8.0...v0.9.0) (2026-11-05)


### Features

* let project git hooks call sail and docker compose in worktrees unchanged ([3f22222](https://github.com/anthonyiles/worktree-isolation/commit/3f222227eb267f4ce6606a1b8937ec8f18f02118))
* let project git hooks call sail and docker compose in worktrees unchanged ([#39](https://github.com/anthonyiles/worktree-isolation/issues/39)) ([7f811a1](https://github.com/anthonyiles/worktree-isolation/commit/7f811a11f447ef00aef2bdad27f8150aaaf7e23f))

## [0.8.0](https://github.com/anthonyiles/worktree-isolation/compare/v0.7.0...v0.8.0) (2026-11-05)


### ⚠ BREAKING CHANGES

* per-worktree database and Compose project names change, so existing worktrees get new ones (re-run vendor/bin/worktree setup). Databases created before this aren't recorded, so clean won't drop them. The artisan commands, the PHP classes and WORKTREE_PRUNE are removed, and .worktree-isolation.env is read from the main checkout only.

### Features

* give docker-image containers their compose service's environment ([3299613](https://github.com/anthonyiles/worktree-isolation/commit/3299613ae854bb43230e6e6df166e0b6df938d40))
* let vendor/bin/worktree run commands in the main checkout ([92af138](https://github.com/anthonyiles/worktree-isolation/commit/92af138970b19149dfeb272f3d0e7c09783e7ad6))
* pass WORKTREE_DOCKER_ENV to docker-image containers ([119f75c](https://github.com/anthonyiles/worktree-isolation/commit/119f75c470b769f355c17b39b22a64de2f10a1eb))
* safer, simpler worktree isolation in bash ([b2c238b](https://github.com/anthonyiles/worktree-isolation/commit/b2c238b5c8727a4a2eb63de7960a2434d20942a6))

## [0.7.0](https://github.com/anthonyiles/worktree-isolation/compare/v0.6.0...v0.7.0) (2026-11-04)


### Features

* add worktree prune to remove merged worktrees ([34bc4f4](https://github.com/anthonyiles/worktree-isolation/commit/34bc4f45a36d59c928cb59301d36f54fc38b6438))
* make the branch prune checks against configurable ([4684780](https://github.com/anthonyiles/worktree-isolation/commit/468478089e17240cf8110eb3620dbe8965af2498))
* run a project's own command at the end of setup ([6b46b53](https://github.com/anthonyiles/worktree-isolation/commit/6b46b539e68bc88d50a5c365090f51aec1a7d192))
* warn about project git hooks that call sail ([038c1b9](https://github.com/anthonyiles/worktree-isolation/commit/038c1b9c9ba5a3523b795df248cec34dd4cee531))


### Bug Fixes

* make git work inside the Docker runtimes ([097ff02](https://github.com/anthonyiles/worktree-isolation/commit/097ff02cb80c7655387411ea39b0851e39bd3dc6))
* name per-worktree test databases without needing .env.testing ([69087d1](https://github.com/anthonyiles/worktree-isolation/commit/69087d18dbf864a115a73e7e4600358d6b057ac0))

## [0.6.0](https://github.com/anthonyiles/worktree-isolation/releases/tag/v0.6.0) (2026-11-02)


### Features

* add worktree install --agents to write AI agent instructions ([446d60f](https://github.com/anthonyiles/worktree-isolation/commit/446d60f81648b04cbc79397b7ef1506805a51c31))
* add worktree:clean artisan command for database cleanup ([27fc84c](https://github.com/anthonyiles/worktree-isolation/commit/27fc84c1a746ebe7b6c275e7ee0c2abc8fc9fdaa))
* detect Laravel Sail in worktree install ([162cf71](https://github.com/anthonyiles/worktree-isolation/commit/162cf711c53bb7f14a59892752d4ee717a686d79))
* initial package scaffold ([f46605a](https://github.com/anthonyiles/worktree-isolation/commit/f46605abe6d4c28868cf1dcb673786a7b97a5720))
* isolate Docker Compose stack and project name per worktree ([444c4e8](https://github.com/anthonyiles/worktree-isolation/commit/444c4e8bded3d56dc3af1950d37e33745bf7587e))
* per-worktree development databases ([d80f2b4](https://github.com/anthonyiles/worktree-isolation/commit/d80f2b4906afe58f896861438d00d419cd3e0153))
* run worktree install without PHP on the host ([a731e5b](https://github.com/anthonyiles/worktree-isolation/commit/a731e5b18ce7de84218bec260ef4f0581ed98a04))
* unify worktree scripts into a single vendor/bin/worktree command ([f6fca81](https://github.com/anthonyiles/worktree-isolation/commit/f6fca819fc888d726a5f26da27ebea0aad4fd28d))


### Bug Fixes

* bake per-worktree database into .env.testing at bootstrap time ([58eafbd](https://github.com/anthonyiles/worktree-isolation/commit/58eafbd6ffe56e1f682bfb2bfe372d851fe61c1d))
* derive database names in bash only, independent of the locale ([429b8f3](https://github.com/anthonyiles/worktree-isolation/commit/429b8f3dfc405c18017cd18c9af8d1b7df3cc991))
* handle an empty WORKTREE_EXTRA_ENV_VARS on bash &lt; 4.4 ([2434e97](https://github.com/anthonyiles/worktree-isolation/commit/2434e97a08c49cdd30765424b3140e71986768c3))
* harden setup's env writing and database naming ([98ff678](https://github.com/anthonyiles/worktree-isolation/commit/98ff678324856d38f0b6351edeaa650eab847c64))
* harden setup/test database handling and dispatcher edge cases ([b067c7c](https://github.com/anthonyiles/worktree-isolation/commit/b067c7cd01ddf7d13a5dfea8a1c584812f90fc91))
* keep database credentials off the command line ([68f7e05](https://github.com/anthonyiles/worktree-isolation/commit/68f7e05c8afc1137564971270e1130323b8d11cb))
* keep worktree-clean going past an unreachable database server ([d4accb2](https://github.com/anthonyiles/worktree-isolation/commit/d4accb2185a4688ad1a69067d02cd1f49883bdf4))
* lock each worktree to its own databases ([df019c1](https://github.com/anthonyiles/worktree-isolation/commit/df019c15596e1c83c0b65e582ccc9bae922c71b6))
* make the JavaScript install in setup optional ([b1576a6](https://github.com/anthonyiles/worktree-isolation/commit/b1576a6615d8a00b23b89ed2780047604dee99c2))
* parse env files instead of sourcing them ([7dd3327](https://github.com/anthonyiles/worktree-isolation/commit/7dd3327381f39dd8f8827c3c2e0b702b8a8e15b2))
* preserve compose file path as a single argument in worktree dispatcher ([086f3a5](https://github.com/anthonyiles/worktree-isolation/commit/086f3a519f3c1d83f95a2746be3201bc4a822dee))
* register worktree hook via absolute path instead of committed relative config ([67eb027](https://github.com/anthonyiles/worktree-isolation/commit/67eb02727996374560c37705fc083cd846a4f31b))
* reject unknown options in worktree clean ([53bc174](https://github.com/anthonyiles/worktree-isolation/commit/53bc17468f5e48b2a63b706cdf37279f6f9e0399))
* require .worktree-isolation.env and tidy the shell scripts ([2909f43](https://github.com/anthonyiles/worktree-isolation/commit/2909f434211bf125f922ea23e1edffe6722d8046))
* run artisan worktree:clean through the configured runtime ([b2a6dc5](https://github.com/anthonyiles/worktree-isolation/commit/b2a6dc566ebb1bab204ebc5a3e4abe1cde488e0d))
* run Docker runtime commands as the host user ([13b5ad2](https://github.com/anthonyiles/worktree-isolation/commit/13b5ad2dad9d0622be95c9988de55db24e0f25ed))
* run sub-scripts and the setup hook through their interpreter ([63ea5c4](https://github.com/anthonyiles/worktree-isolation/commit/63ea5c458e18e44413d0a77237b3e754f3a8d6a3))
* run worktree clean inside the Docker runtime ([0b99a8d](https://github.com/anthonyiles/worktree-isolation/commit/0b99a8d81da13fa3d68dad00445a089394f7cd8d))
* support PHP 8.2 by dropping typed class constants ([3970b50](https://github.com/anthonyiles/worktree-isolation/commit/3970b5091d02fea75b305e5256a9fd7dbfb2e811))
* truncate overlong per-worktree database names instead of failing ([0fdc018](https://github.com/anthonyiles/worktree-isolation/commit/0fdc018e9dca702a7cb1d5ba5bed1861dba13d69))


### Miscellaneous Chores

* version the package as 0.x until it's ready for 1.0 ([1a0db31](https://github.com/anthonyiles/worktree-isolation/commit/1a0db31276ad99d823f3aba12142f9161d545858))
