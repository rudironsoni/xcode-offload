# Changelog

## Unreleased

- Add CI, release automation, changelog generation, and build metadata plumbing.
- Add strict doctor checks for sparsebundle readability, APFS filesystems, cache
  provenance, plist linting, and launchd last exit status.
- Add repair command to compose init, mount, launchd, and optional shim actions.
- Add repair scope and privilege preflight so non-root repair can target user
  launchd assets without partially attempting system launchd installation.
