# SQL Database Exporter

PowerShell utility to export SQL Server user tables and their data to CSV files in one run.

The script discovers user tables from SQL Server catalog views, applies an export profile, and streams every selected table to a UTF-8 CSV file. Readers run concurrently. Each reader streams rows instead of loading a whole table into memory.

Validate the exporter against a disposable database before using it with production data.

## Purpose

Copying an entire SQL Server database to CSV by hand is slow and easy to do incompletely. This utility discovers the current user tables, skips tables excluded by a named profile, and writes one CSV file per selected table plus a JSON manifest for that run.

## Features

The implementation supports:

- Microsoft SQL Server access through `System.Data.SqlClient` and T-SQL catalog views.
- Windows PowerShell 5.1 on Windows. PowerShell 7 was not available in the environment used to prepare this repository, and support for it is not claimed.
- Two example profiles, `standard` and `full`, defined in [`export-profiles.json`](export-profiles.json).
- Discovery of user tables (`sys.tables` where `is_ms_shipped = 0`). Views are not exported.
- Optional comparison against the synthetic table names in [`schema-reference.json`](schema-reference.json). The comparison does not limit the export.
- A positional `top N` limit applied independently to each table, without `ORDER BY`.
- SQL authentication and Windows integrated authentication.
- Settings from parameters, process environment variables, or a local `.env` file.
- Parallel streaming readers, UTF-8 CSV, and a per-run `manifest.json`.
- `-DryRun` to list selected tables, and `-ValidateOnly` to compile the exporter without connecting.

## Prerequisites

- Windows PowerShell 5.1. The script references `System.Data.dll`, which supplies `System.Data.SqlClient` on .NET Framework. No separate PowerShell SQL module is required.
- Network access from the machine running the script to the SQL Server instance.
- A database login that can connect, read the catalog views the script queries, and `SELECT` from every table being exported.

Details are in [docs/installation.md](docs/installation.md).

## Installation

Clone or copy this repository, then create a local `.env` file from the example:

```powershell
Copy-Item .env.example .env
```

Edit `.env` with a SQL Server host, database name, and credentials. `.env` is ignored by Git. Do not commit it.

You can also pass `-ServerInstance`, `-Database`, `-Username`, and `-Password` on the command line. A password on the command line can be stored in shell history and process listings. Prefer `.env` or a process environment variable.

## Usage

Run from the repository root in Windows PowerShell:

```powershell
.\data-export.ps1 YOUR_CLIENT standard
```

That single command connects, discovers user tables, applies the `standard` profile, and writes CSV files for every selected table. `YOUR_CLIENT` replaces the `{client}` token in `SQL_DATABASE` and is used in file names. It is an export label, not necessarily a person's name.

The same implementation can be called directly:

```powershell
.\src\Export-SqlDatabaseToCsv.ps1 YOUR_CLIENT standard
```

`data-export.ps1` forwards its arguments to `src/Export-SqlDatabaseToCsv.ps1`.

Export with the other profile, or limit each table to 10 rows:

```powershell
.\data-export.ps1 YOUR_CLIENT full
.\data-export.ps1 YOUR_CLIENT full top 10
.\data-export.ps1 YOUR_CLIENT full -Top 10
```

`TOP` is applied without `ORDER BY`. The rows are not a stable or ordered sample.

Preview the selected tables without writing CSV files:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -DryRun
```

Check the JSON profiles and compile the embedded exporter without opening a connection:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly
```

More commands, authentication examples, and output details are in [docs/usage.md](docs/usage.md). Parameters and environment variables are in [docs/configuration.md](docs/configuration.md).

## How a table becomes a CSV file

1. The script opens one connection and reads user tables from `sys.tables`, `sys.schemas`, and `sys.partitions`.
2. It drops tables whose schema, or table-name prefix, is excluded by the selected profile.
3. It creates a UTC timestamped directory under the output root.
4. For each selected table it opens a connection, reads column metadata, and runs `SELECT` of those columns. Assembly types are converted with `CONVERT(varbinary(max), column)`.
5. Rows are written as comma-separated, quoted fields. SQL `NULL` is an empty unquoted field. Binary values are Base64. Date and time values use invariant-culture formats.
6. The run writes `manifest.json` with counts, durations, excluded objects, schema-reference differences, and failures.

The default output root is `exports` in the repository root. A run directory looks like this:

```text
exports/YOUR_CLIENT_standard_20260804_143500/
  YOUR_CLIENT_Customers_20260804.csv
  YOUR_CLIENT_sales_Orders_20260804.csv
  manifest.json
```

`dbo` is omitted from the file name. Any other schema is included as a prefix. The time in the directory name is UTC. File names replace characters that are illegal in Windows paths.

Override the location with `-OutputRoot 'D:\SQL-Exports'` or `EXPORT_ROOT`.

## Configuration and authentication

Precedence for each setting is:

1. The matching parameter, when it is supplied.
2. The process environment variable.
3. The same name in `.env`.
4. The default documented in [docs/configuration.md](docs/configuration.md).

`SQL_DATABASE={client}` means the first command argument is the database name. Other patterns, such as `{client}_reporting`, are replaced literally. `{profile}` is also replaced.

```powershell
.\data-export.ps1 YOUR_CLIENT standard -Authentication Integrated -ServerInstance 'sql01.example.com' -Database 'YOUR_DATABASE'
```

The connection string sets `Application Name` to `SQL Database Exporter`. That value is visible to SQL Server.

`-Encrypt` and `-TrustServerCertificate` are combined with `SQL_ENCRYPT` and `SQL_TRUST_SERVER_CERTIFICATE` using OR. Passing the switch turns the flag on. The switch does not turn the flag off when the environment value is already true. The defaults are `false`, which preserves the existing behavior. Set `SQL_ENCRYPT=true` when the server requires TLS. Leave trust-server-certificate off unless you have a specific reason to skip certificate-chain validation.

## Errors, logging, and troubleshooting

The script stops on a missing server, a missing database, SQL authentication without a user and password, or a profile that selects no tables. Progress lines go to the host. A failed table prints a sanitized error to the error stream, deletes that table's incomplete CSV, and continues with the other tables. After all tables finish, the script writes the manifest and then throws if any table failed.

The script is written so that it does not print the password or the connection string. Error text is additionally scrubbed for `Password=` values and for the password itself when that password is at least 8 characters. Do not treat this as a guarantee that every possible provider message is free of sensitive text. Review errors before sharing them.

There is no separate log file. The host output and `manifest.json` are the record of a run. The manifest contains the server name, database name, table names, and error text. It does not contain the password field from the connection string.

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Security and privacy

CSV files contain whatever the source tables contain. That can include personal data, financial records, and credentials stored by the application. Export only when you are authorized to copy that data, and protect the `exports` directory.

Use a login limited to the tables you intend to export. Do not hardcode passwords. Do not commit `.env`, CSV files, manifests from real runs, or local workbooks.

This repository does not send exported data, telemetry, or analytics to a third party.

Read [docs/security.md](docs/security.md) and [docs/privacy-review.md](docs/privacy-review.md) before publishing or running the exporter against a production database. Nothing in this repository certifies compliance with GDPR or any other law.

## Known limitations

- SQL Server only, through the .NET Framework SQL client used by Windows PowerShell 5.1. Other engines are not implemented.
- User tables only. Views, procedures, and synonym targets are not exported.
- Profile filters are the two example profiles shipped in `export-profiles.json`. Copy that file and edit the exclusion lists for your database. The `-Profile` parameter only accepts `standard` and `full` until you change its `ValidateSet`.
- `schema-reference.json` is a synthetic list of table names for comparison. It is not a customer schema and it does not filter the export.
- `TOP` without `ORDER BY` does not define which rows return.
- Each table is read independently. This is not a single transactional snapshot. Use a database snapshot or a restored backup when you need one point in time.
- Partition row counts are estimates from `sys.partitions`, and they can be stale.
- Two different table names can sanitize to the same file name. The later writer would overwrite that file.
- `-CommandTimeoutSeconds 0` waits indefinitely.
- Several parallel readers create several connections. A large export can load the SQL Server and fill the output disk even though each reader streams rows.
- Public visibility of a GitHub repository does not, by itself, grant permission to use, modify, or redistribute the code. A completed license does that.

## Documentation

- [Installation](docs/installation.md)
- [Usage](docs/usage.md)
- [Configuration](docs/configuration.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security](docs/security.md)
- [Privacy review](docs/privacy-review.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Do not include credentials, real exports, or private customer information.

Report security problems through the process in [SECURITY.md](SECURITY.md). A private reporting channel is not configured yet.

## License

The license file is the MIT License, a permissive license that allows use, modification, and redistribution when its conditions are met. Choosing MIT for this utility is a maintainer decision. It is not a claim that MIT is the right license for every organization.

The copyright line uses the GitHub account `mohammadusman` and the year 2026. No earlier license or copyright notice was present in this project. Replace that line with the legal copyright holder if the GitHub account name is not the owner you want to publish.

## Disclaimer

Test the exporter on a non-production database and review the CSV files before you depend on them. The authors and copyright holders provide the software as-is, without warranty, as stated in the license.
