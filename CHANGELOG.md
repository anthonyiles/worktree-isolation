# Changelog

## [1.4.0](https://github.com/anthonyiles/worktree-isolation/compare/v1.3.0...v1.4.0) (2026-09-24)


### Features

* detect Laravel Sail in worktree install ([162cf71](https://github.com/anthonyiles/worktree-isolation/commit/162cf711c53bb7f14a59892752d4ee717a686d79))


### Bug Fixes

* handle an empty WORKTREE_EXTRA_ENV_VARS on bash &lt; 4.4 ([2434e97](https://github.com/anthonyiles/worktree-isolation/commit/2434e97a08c49cdd30765424b3140e71986768c3))
* run Docker runtime commands as the host user ([13b5ad2](https://github.com/anthonyiles/worktree-isolation/commit/13b5ad2dad9d0622be95c9988de55db24e0f25ed))
* run worktree clean inside the Docker runtime ([0b99a8d](https://github.com/anthonyiles/worktree-isolation/commit/0b99a8d81da13fa3d68dad00445a089394f7cd8d))

## [1.3.0](https://github.com/anthonyiles/worktree-isolation/compare/v1.2.0...v1.3.0) (2026-09-24)


### Features

* add worktree install --agents to write AI agent instructions ([446d60f](https://github.com/anthonyiles/worktree-isolation/commit/446d60f81648b04cbc79397b7ef1506805a51c31))

## [1.2.0](https://github.com/anthonyiles/worktree-isolation/compare/v1.1.0...v1.2.0) (2026-09-23)


### Features

* per-worktree development databases ([d80f2b4](https://github.com/anthonyiles/worktree-isolation/commit/d80f2b4906afe58f896861438d00d419cd3e0153))
* unify worktree scripts into a single vendor/bin/worktree command ([f6fca81](https://github.com/anthonyiles/worktree-isolation/commit/f6fca819fc888d726a5f26da27ebea0aad4fd28d))


### Bug Fixes

* harden setup's env writing and database naming ([98ff678](https://github.com/anthonyiles/worktree-isolation/commit/98ff678324856d38f0b6351edeaa650eab847c64))
* harden setup/test database handling and dispatcher edge cases ([b067c7c](https://github.com/anthonyiles/worktree-isolation/commit/b067c7cd01ddf7d13a5dfea8a1c584812f90fc91))
* keep worktree-clean going past an unreachable database server ([d4accb2](https://github.com/anthonyiles/worktree-isolation/commit/d4accb2185a4688ad1a69067d02cd1f49883bdf4))
* lock each worktree to its own databases ([df019c1](https://github.com/anthonyiles/worktree-isolation/commit/df019c15596e1c83c0b65e582ccc9bae922c71b6))
* preserve compose file path as a single argument in worktree dispatcher ([086f3a5](https://github.com/anthonyiles/worktree-isolation/commit/086f3a519f3c1d83f95a2746be3201bc4a822dee))
* run sub-scripts and the setup hook through their interpreter ([63ea5c4](https://github.com/anthonyiles/worktree-isolation/commit/63ea5c458e18e44413d0a77237b3e754f3a8d6a3))

## [1.1.0](https://github.com/anthonyiles/worktree-isolation/compare/v1.0.0...v1.1.0) (2026-09-17)


### Features

* isolate Docker Compose stack and project name per worktree ([444c4e8](https://github.com/anthonyiles/worktree-isolation/commit/444c4e8bded3d56dc3af1950d37e33745bf7587e))

## 1.0.0 (2026-09-02)


### Features

* add worktree:clean artisan command for database cleanup ([27fc84c](https://github.com/anthonyiles/worktree-isolation/commit/27fc84c1a746ebe7b6c275e7ee0c2abc8fc9fdaa))
* initial package scaffold ([f46605a](https://github.com/anthonyiles/worktree-isolation/commit/f46605abe6d4c28868cf1dcb673786a7b97a5720))


### Bug Fixes

* bake per-worktree database into .env.testing at bootstrap time ([58eafbd](https://github.com/anthonyiles/worktree-isolation/commit/58eafbd6ffe56e1f682bfb2bfe372d851fe61c1d))
* register worktree hook via absolute path instead of committed relative config ([67eb027](https://github.com/anthonyiles/worktree-isolation/commit/67eb02727996374560c37705fc083cd846a4f31b))
