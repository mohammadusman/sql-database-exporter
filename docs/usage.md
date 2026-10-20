# Usage

Run the commands in Windows PowerShell from the repository root. Replace `YOUR_CLIENT` and any host or database names. Do not use a production password on the command line.

## Export every selected table

```powershell
.\data-export.ps1 YOUR_CLIENT standard
```

This is a single execution. The script connects, discovers user tables, removes tables excluded by `standard`, writes one CSV per remaining table, and writes `manifest.json`.

```powershell
.\data-export.ps1 YOUR_CLIENT full
```

The direct script path accepts the same arguments:

```powershell
.\src\Export-SqlDatabaseToCsv.ps1 YOUR_CLIENT standard
```

## Limit rows

```powershell
.\data-export.ps1 YOUR_CLIENT standard top 10
.\data-export.ps1 YOUR_CLIENT standard -Top 10
```

The positional form requires the keyword `top` and then a positive integer. Each selected table is queried with `SELECT TOP (@rowLimit)`. There is no `ORDER BY`, so SQL Server does not define which rows those are.

If `top` is present without a count, the script throws before it connects: the positional `top` keyword must be followed by a positive record count.

## Choose a database and server

With `.env` containing `SQL_DATABASE={client}`, the command above exports the database named `YOUR_CLIENT`.

To use another database name:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -Database 'YOUR_DATABASE'
```

Or set `SQL_DATABASE={client}_archive` in `.env`. The tokens `{client}` and `{profile}` are replaced with the exact argument text after settings are resolved. Replacement is case-sensitive.

## Authentication

SQL authentication from `.env` is the normal path. `SQL_AUTHENTICATION=Sql` requires `SQL_USER` and `SQL_PASSWORD`.

An explicit command, shown with placeholders only:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ServerInstance 'sql01.example.com' -Database 'YOUR_DATABASE' -Username 'export_user' -Password 'your-password'
```

Windows integrated authentication:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ServerInstance 'sql01.example.com' -Database 'YOUR_DATABASE' -Authentication Integrated
```

Integrated authentication does not read `SQL_USER` or `SQL_PASSWORD`.

## Profiles

`standard` excludes:

- schemas `audit` and `staging`
- table names that start with `tmp_` or `backup_`, in any case

`full` excludes:

- schema `audit`
- table names that start with `tmp_`, in any case

Exclusions are defined in `export-profiles.json`. They are compared as schema name or table-name prefix, not as a three-part name.

## Preview and validate

List the tables that would be exported. This still connects and reads catalog views. It does not write CSV files:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -DryRun
```

Each line is `schema.table` and the estimated row count from `sys.partitions`.

Compile and load the profile without a connection:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly
```

## Output location and file names

The default root is the `exports` directory in the repository root. Relative values of `-OutputRoot` and `EXPORT_ROOT` are resolved from that same root when the script is loaded from `src`.

```powershell
.\data-export.ps1 YOUR_CLIENT standard -OutputRoot 'D:\SQL-Exports'
```

Each run creates a directory:

```text
{safe-client}_{safe-profile}_{yyyyMMdd_HHmmss}
```

The timestamp is UTC.

Each table becomes:

```text
{safe-client}_{safe-table}_{yyyyMMdd}.csv
```

For a schema other than `dbo`:

```text
{safe-client}_{safe-schema}_{safe-table}_{yyyyMMdd}.csv
```

Example:

```text
exports/YOUR_CLIENT_standard_20260804_143500/YOUR_CLIENT_Customers_20260804.csv
exports/YOUR_CLIENT_standard_20260804_143500/manifest.json
```

Characters that are illegal in Windows file names are replaced. If the safe name differs from the original, or is longer than 36 characters, the file component is shortened and a 10-character SHA-256 prefix is appended. The goal is a legal path, not a reversible encoding of every original name.

## CSV format

- Encoding is UTF-8 with a byte-order mark.
- The delimiter is a comma.
- The first row is the column names, each quoted.
- Non-null values are quoted. A double quote inside a value is doubled.
- SQL `NULL` is written as an empty field and is not quoted.
- `date` values use `yyyy-MM-dd`.
- `datetime` and `datetime2` values use `yyyy-MM-ddTHH:mm:ss.fffffff`.
- `datetimeoffset` uses the round-trip `o` format.
- `time` uses the constant `c` format.
- Floating-point values use round-trip `R`.
- Other formattable values use the invariant culture.
- `binary`, `varbinary`, and `image` values are Base64. Columns whose SQL type is an assembly type are converted to `varbinary(max)` before that encoding.

The manifest is UTF-8 without a byte-order mark. It records the client label, profile, server, database, filters, excluded objects, per-table counts, byte sizes, durations, schema-reference differences, and errors.

## Schema reference

If `schema-reference.json` exists, the script compares its `tables` array with the table names discovered in the database. Names present only in the database, and names present only in the reference, are stored in the manifest. Both sets are matched by table name, not by schema. The export still uses the live catalog.

## Parallelism and timeouts

```powershell
.\data-export.ps1 YOUR_CLIENT standard -Parallelism 8 -ConnectionTimeoutSeconds 30 -CommandTimeoutSeconds 0
```

`-Parallelism` is the maximum number of tables read at the same time. The default is 4. Each reader uses its own connection.

`-CommandTimeoutSeconds 0` means no command timeout. That is the default.

## Failure behavior

A table that fails does not keep a partial CSV. That file is deleted when the delete succeeds. Other tables continue. The process then writes the manifest and throws, reporting how many tables failed and the manifest path.

Catalog connection failures, missing configuration, and validation errors throw before CSV files are written.

## Related documents

- [Configuration](configuration.md)
- [Troubleshooting](troubleshooting.md)
- [Security](security.md)
