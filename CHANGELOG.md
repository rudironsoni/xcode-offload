## 0.1.0 (2026-07-02)


### Features

* add launchd and daemon install aliases ([71c984f](https://github.com/rudironsoni/xcode-storage/commit/71c984f47fae75defa7948f3e4a26444c664a4df))
* scaffold xcode storage cli ([978cc84](https://github.com/rudironsoni/xcode-storage/commit/978cc84f9a38b67cd2f97ba3441b99a85bff5e4f))


### Bug Fixes

* add launchd hooks without machine defaults ([5fffcd4](https://github.com/rudironsoni/xcode-storage/commit/5fffcd40f2398b33c7de740ae2cd4ca31b4b3557))
* add strict doctor and repair checks ([b70d207](https://github.com/rudironsoni/xcode-storage/commit/b70d2070093d859fd0bcfab47ab274f877f69707))
* create privileged launchd target directories ([c9f5ffd](https://github.com/rudironsoni/xcode-storage/commit/c9f5ffdbc0c41d7f60d2bde66ed25a5a3eac2bed))
* scope repair and preflight system launchd ([dc8fe95](https://github.com/rudironsoni/xcode-storage/commit/dc8fe9538b71b5a2baed632ad314b21663803d54))

# Changelog

## Unreleased

- Add CI, release automation, changelog generation, and build metadata plumbing.
- Add strict doctor checks for sparsebundle readability, APFS filesystems, cache
  provenance, plist linting, and launchd last exit status.
- Add repair command to compose init, mount, launchd, and optional shim actions.
- Add repair scope and privilege preflight so non-root repair can target user
  launchd assets without partially attempting system launchd installation.
