# Changelog

## v0.1.0 - 2026-07-02

- ci: add prepared release workflow (2b1500d)
- docs: clarify launchd install flow (82056ea)
- feat: add launchd and daemon install aliases (71c984f)
- test: cover semver build metadata generation (14ba796)
- fix: create privileged launchd target directories (c9f5ffd)
- ci: use maintained semver release validation (294a178)
- fix: scope repair and preflight system launchd (dc8fe95)
- fix: add strict doctor and repair checks (b70d207)
- ci: support github runner swift version (165c65b)
- ci: add build test and release automation (c8ef08c)
- fix: add launchd hooks without machine defaults (5fffcd4)
- feat: scaffold xcode storage cli (978cc84)

## Unreleased

- Add CI, release automation, changelog generation, and build metadata plumbing.
- Add strict doctor checks for sparsebundle readability, APFS filesystems, cache
  provenance, plist linting, and launchd last exit status.
- Add repair command to compose init, mount, launchd, and optional shim actions.
- Add repair scope and privilege preflight so non-root repair can target user
  launchd assets without partially attempting system launchd installation.
