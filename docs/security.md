# Security

This page describes how the exporter handles credentials and exported data. It is engineering guidance. It is not a certification, a penetration test, or a compliance claim.

## Least privilege

Create a SQL Server login used only for export. Grant `CONNECT` on one database, `SELECT` on the tables that the chosen profile is allowed to copy, and catalog visibility for those tables. Do not grant `sysadmin`, `db_owner`, or write permissions for this job.

The profile filters are application-level exclusions. They are not a security boundary. A login that can `SELECT` from a table can be used, by a modified script or another client, to read that table. Enforce the boundary in SQL Server.

Discovery lists user tables the caller can see, including tables the profile later skips. Keep sensitive schemas inaccessible to the export login if those schemas must not be read by this account.

## Credential handling

Supported places for a SQL password:

- The untracked `.env` file (`SQL_PASSWORD`)
- A process environment variable (`SQL_PASSWORD`)
- The `-Password` parameter

Prefer `.env` or a process environment variable. `-Password` exposes the value to shell history and to tools that record process command lines.

The script does not write the password or the full connection string to the host on the success path. Connection setup prints only the server and database names. Export errors pass through a scrubber that replaces `Password=` values and, for a password of at least 8 characters, exact occurrences of that password in the exception text.

Limits of that scrubber, from the code:

- A password shorter than 8 characters is not removed by the exact-text replacement. The `Password=` pattern is still applied.
- User names, server names, database names, and SQL text can remain in provider errors.
- `manifest.json` stores the server, the database, and the scrubbed error. It does not have a password field. Treat the manifest as sensitive anyway, because error text and names can identify the environment.
- The password is still held in memory as a .NET string because `SqlConnectionStringBuilder` requires one. It is not stored as a `SecureString`. That matches the existing authentication behavior.

Do not hardcode a password in `data-export.ps1`, `src/Export-SqlDatabaseToCsv.ps1`, `export-profiles.json`, or documentation.

Integrated authentication avoids a SQL password. It uses the Windows identity of the process. Protect that identity the same way you protect any other principal that can read the database.

## Connection strings

The string is built with `SqlConnectionStringBuilder` and passed to `SqlConnection`. It is not printed by the script's own progress messages.

`Encrypt` defaults to false. That preserves the original behavior and can allow an unencrypted SQL connection when the server permits it. Set `SQL_ENCRYPT=true` for servers that support TLS, including typical Azure SQL configurations. This repository did not execute a connection, so it does not claim a particular server setting works.

`TrustServerCertificate` defaults to false. Turning it on disables normal certificate-chain checks. Leave it false unless you have a separate reason to accept that risk.

`Application Name` is set to `SQL Database Exporter`. Database administrators can see that name in session information.

## Exported files

Every selected column of every selected table is written to disk. The CSV can contain personal data, secrets stored in the database, tokens, and financial or property records. The exporter cannot know which columns are sensitive.

Protect `exports`:

- Write it to a disk and directory that only the export operators can read.
- Do not put it in a public file share, a web root, a synced personal drive, or a Git repository.
- Encrypt the disk or the directory when the data warrants it.
- Decide a retention period, then delete the run directory, including `manifest.json`, when the export is no longer needed.
- Do not send the CSV files to a third party unless that disclosure is authorized.

`.gitignore` excludes `.env`, `exports/`, `*.csv`, and workbook files. Git ignore rules do not untrack a file that was committed before the rule existed. This project directory was not a Git repository at the time of review, so there was no commit history to clean. See [privacy-review.md](privacy-review.md).

## Logging

Host output includes connection targets, table names, row counts, durations, and the manifest path. Failed tables include sanitized exception text. There is no telemetry and no upload of the CSV contents. Do not add one.

Review host transcripts before attaching them to a ticket. They contain the server and database names.

## Production data

Exporting production data creates another copy of that data, with its own access control and backup life cycle. Prefer a restored backup or a snapshot when you need a consistent point in time. The script reads each table separately and does not wrap the run in one transaction.

Run `-ValidateOnly` first, then `-DryRun`, then a limited `-Top` export, then a full export. Confirm you are pointed at the intended server before a full run. The local `.env` in a developer folder may point at a live server.

## If a secret is exposed

Rotate the database password and any other exposed credential. Remove the secret from files you are about to publish. If it was committed, rotating is still required after history is cleaned, and history cleaning needs an explicit maintainer decision. A new commit that deletes the secret does not remove it from old commits.
