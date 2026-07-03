## [0.2.0](https://github.com/rudironsoni/xcode-storage/compare/v0.1.0...v0.2.0) (2026-07-03)


### Features

* add native certification command ([61d332d](https://github.com/rudironsoni/xcode-storage/commit/61d332d9b56c393e6ebdb11d3d70a6d5bac5e444))
* add native transparent storage mode ([7f6c857](https://github.com/rudironsoni/xcode-storage/commit/7f6c8571423c0f09d2790df62bdb0bf8f3ac7db9))


### Bug Fixes

* harden CoreSimulator mount management ([2dde021](https://github.com/rudironsoni/xcode-storage/commit/2dde021669d8fe05e48b9d98251ead0f54c74b36))
* harden native storage verification ([5ca1b2b](https://github.com/rudironsoni/xcode-storage/commit/5ca1b2bf9f91727cde257227bde37008b7111443))
* make native dry-runs fail closed ([cdf44e2](https://github.com/rudironsoni/xcode-storage/commit/cdf44e2347c6b7bd322d14c7414abbd9840d30cd))
* make simulator open idempotent ([bc3090c](https://github.com/rudironsoni/xcode-storage/commit/bc3090c090bbe611e0f30b1019fa072cc54c92d8))
* normalize cli smoke temp paths ([e35c87e](https://github.com/rudironsoni/xcode-storage/commit/e35c87e2a142ad284aa490b81708f010c86cc5b5))
* reject native wrong-backend mounts ([56f3656](https://github.com/rudironsoni/xcode-storage/commit/56f365600c644fa1633a4936511d6175ad2c16c5))

## 0.1.0 (2026-07-02)


### Features

* add launchd and daemon install aliases ([71c984f](https://github.com/rudironsoni/xcode-storage/commit/71c984f47fae75defa7948f3e4a26444c664a4df))
* scaffold xcode storage cli ([978cc84](https://github.com/rudironsoni/xcode-storage/commit/978cc84f9a38b67cd2f97ba3441b99a85bff5e4f))


### Bug Fixes

* add launchd hooks without machine defaults ([5fffcd4](https://github.com/rudironsoni/xcode-storage/commit/5fffcd40f2398b33c7de740ae2cd4ca31b4b3557))
* add strict doctor and repair checks ([b70d207](https://github.com/rudironsoni/xcode-storage/commit/b70d2070093d859fd0bcfab47ab274f877f69707))
* create privileged launchd target directories ([c9f5ffd](https://github.com/rudironsoni/xcode-storage/commit/c9f5ffdbc0c41d7f60d2bde66ed25a5a3eac2bed))
* scope repair and preflight system launchd ([dc8fe95](https://github.com/rudironsoni/xcode-storage/commit/dc8fe9538b71b5a2baed632ad314b21663803d54))
* use project release tag for build metadata ([7b2902a](https://github.com/rudironsoni/xcode-storage/commit/7b2902ad1e6a2e3f0fa9d6762fbb2214f1237d3f))
* verify release checksums from artifact directory ([c1c1f1c](https://github.com/rudironsoni/xcode-storage/commit/c1c1f1c482160e3f812fd8a0cf6c77fa7a2578d9))
* write portable release checksums ([84261ae](https://github.com/rudironsoni/xcode-storage/commit/84261aef35d306242dbed181883898f3a19dc4f9))

## Unreleased

- Add CI, release automation, changelog generation, and build metadata plumbing.
- Add strict doctor checks for sparsebundle readability, APFS filesystems, cache
  provenance, plist linting, and launchd last exit status.
- Add repair command to compose init, mount, launchd, and optional shim actions.
- Add repair scope and privilege preflight so non-root repair can target user
  launchd assets without partially attempting system launchd installation.
