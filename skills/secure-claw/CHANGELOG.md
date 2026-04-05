# Changelog

## 1.2.1 -- 2026-04-04

### Added
- Rule 8 in SKILL.md: every change to the skill must bump VERSION and add a CHANGELOG entry in the same commit

## 1.2.0 -- 2026-04-04

### Fixed
- Mermaid diagrams now render correctly in `.securecode/diagrams.html` -- added explicit HTML template with `<pre class="mermaid">` tags and ESM module import. Previously diagrams showed as raw code.

### Changed
- Block messages now include full context: GHSA advisory ID, vulnerability summary, affected version range, patched version, resolved installed version, and actionable guidance. Socket blocks include a link to the package's Socket.dev review page.

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
