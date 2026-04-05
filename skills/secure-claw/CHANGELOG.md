# Changelog

## 1.1.0 -- 2026-04-04

### Fixed
- Advisory check no longer blocks packages when the installed version is already patched (e.g., `next-auth@4.24.13` was blocked because advisories existed for versions before 4.10.3)
- Fixed duplicate advisory counting caused by jq `select` with array generator -- now uses `any()` to emit each advisory at most once

### Added
- Version resolution fallback chain: checks node_modules first, then extracts version from the install command (e.g., `next-auth@4.24.13`), then queries the npm registry for latest. Only blocks conservatively when no version can be determined.

## 1.0.0 -- 2026-04-01

- Initial release
- 17-category security checklist with tier-based activation
- Install interception with Socket.dev + GitHub Advisory Database
- Session start/end scanning hooks
- Data flow and auth flow diagram generation
- Scan-first intercept architecture with curl/wget/make detection
