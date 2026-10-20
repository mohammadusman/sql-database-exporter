# Privacy review

Review date: 2026-10-21

Final review status: `Ready for maintainer review`

This review covers the files prepared for the public repository. It does not certify GDPR compliance, or compliance with any other law. A source review cannot prove that every future export is lawful.

## 1. Review scope

The project folder was reviewed before publication. The goal was to keep the SQL Server CSV exporter usable while removing customer-specific schema details, local secrets, and document metadata from the files that will be committed.

No database export was executed. No data was sent to a third party. The exporter does not contain telemetry.

## 2. Files and file types inspected

- PowerShell scripts: `data-export.ps1`, `src/Export-SqlDatabaseToCsv.ps1`, and `tests/Invoke-ExporterValidation.ps1`
- JSON: `export-profiles.json`, `schema-reference.json`
- Environment files: `.env.example` and the local `.env`
- Documentation and GitHub templates
- `.gitignore`
- One local Excel workbook that was already in the folder
- Directory listing, including hidden files at the repository root

No CSV export output was present. Git was not initialized at the start of the review, so there were no commits, branches, tags, or remotes to inspect.

## 3. Types of information checked

- Personal names, account names, and contact details
- Customer, client, and employee identifiers
- Server names, host names, private addresses, database names, and tenant identifiers
- Local paths that include a user or organization
- Passwords, connection strings, tokens, and keys
- Real table inventories and exported records
- Workbook metadata, including document properties and sensitivity-label properties

## 4. Findings

### High

The local `.env` file contains a cloud SQL host, a SQL login, and a password. Those values are not repeated here. `.env` is listed in `.gitignore`. It was not part of a Git commit because the folder was not a repository during the review.

The local workbook contains a personal name in its creator property, a Windows path that includes a user profile and a client directory, a client name in worksheet values, and Microsoft 365 sensitivity-label properties that include a tenant identifier. Those values are not repeated here. Workbooks are ignored by `.gitignore`.

### Medium

The original `schema-reference.json` was a real application table inventory, including objects used for accounts and tokens. That inventory was replaced with five synthetic names: `Customers`, `Orders`, `OrderLines`, `Products`, and `Categories`.

The original profile names and exclusion lists identified a specific application. They were replaced with the example profiles `standard` and `full`, which exclude synthetic schemas (`audit`, `staging`) and synthetic prefixes (`tmp_`, `backup_`).

The SQL application name and the embedded type namespace were renamed so they no longer use the original product name.

### Low

An earlier README draft contained an absolute local workspace path. The published README uses relative `exports` paths and synthetic file names.

## 5. Remediation performed

- Replaced the schema reference and export profiles with synthetic examples.
- Renamed the connection application name to `SQL Database Exporter`.
- Renamed the embedded namespace to `SqlCsvExport`.
- Ignored `.env`, `exports/`, `*.csv`, workbooks, logs, and private-key file types.
- Left `.env` and the workbook on disk so the local working copy was not destroyed. They are not intended to be committed.
- Added password scrubbing for export error text. This does not change CSV contents.
- Did not add telemetry or any upload of exported data.

## 6. Git history exposure

There was no Git repository in this folder at the start of the review, so this review could not find historical commits. The first commit should contain only the sanitized files. If these files were copied from another repository, backup, or chat, that other copy was not reviewed and may still contain the original schema or secrets.

`.gitignore` does not remove a file after it has been committed. The initial commit needs to be checked so `.env`, workbooks, and CSV files are absent.

## 7. Checks that could not be completed

- A live database export was not run.
- PowerShell 7 was not installed.
- Copies of this project outside the current folder were not searched.
- This review cannot prove that no sensitive string remains merely because the scans below found none.

## 8. Remaining risks and manual actions

- Rotate the SQL password stored in the local `.env`. It was present in plaintext in the project folder. Rotation is recommended even though that file is not part of the public commit.
- Do not run `git add -f` on `.env`, the workbook, or `exports/`.
- Keep real exports and real schema lists out of issues, pull requests, and examples.
- CSV files produced by users of this tool can contain personal data. Users need authorization to export that data and need to protect the output.
- The copyright line uses the GitHub account name `mohammadusman`. Change `LICENSE` if a different legal owner should be named.
- Enable GitHub private vulnerability reporting, or add a monitored contact in `SECURITY.md`. Neither is configured by this repository alone.

## 9. Publication scan

Before the first commit, the published text files were checked for a public Azure SQL hostname suffix and for the original customer profile and schema files. The local `.env` and workbook remain the places where the original secrets and document metadata reside, and they are excluded from Git.
