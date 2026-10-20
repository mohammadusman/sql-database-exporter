# Changelog

## [Unreleased]

### Added

- Repository documentation, GitHub issue and pull request templates, and a PowerShell validation workflow.
- Comment-based help on the exporter.
- Scrubbing of password text in export error messages written to the console and `manifest.json`.

### Changed

- Moved the exporter implementation to `src/Export-SqlDatabaseToCsv.ps1`.
- Kept `data-export.ps1` as a compatibility wrapper that forwards arguments to that script.
- Published example profiles and a synthetic schema-reference list.

No earlier public releases are recorded in this repository.
