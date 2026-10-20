# Configuration

The exporter reads settings in this order: parameter, process environment variable, `.env`, then the default. There is no other configuration format.

An example `.env` file is [`.env.example`](../.env.example). Copy it to `.env` and replace the placeholders. Do not put real passwords in documentation or in Git.

## Parameters

| Parameter | Position | Required | Allowed values | Environment name | Default |
| --- | --- | --- | --- | --- | --- |
| `ClientName` | 0 | Yes | Non-empty string | None | None |
| `Profile` | 1 | Yes | `standard`, `full` | None | None |
| `RowLimitKeyword` | 2 | No | `top` | None | None |
| `Top` | 3 | No | Integer 1 through 2147483647 | None | Unlimited when omitted |
| `ServerInstance` | Named | No | String | `SQL_SERVER` | None. The run fails before connecting if this is empty |
| `Database` | Named | No | String | `SQL_DATABASE` | `{client}` |
| `Username` | Named | No | String | `SQL_USER` | None |
| `Password` | Named | No | String | `SQL_PASSWORD` | None |
| `Authentication` | Named | No | `Sql`, `Integrated` | `SQL_AUTHENTICATION` | `Sql` |
| `OutputRoot` | Named | No | String | `EXPORT_ROOT` | `exports` under the project root |
| `EnvFile` | Named | No | String | None | `.env` under the project root |
| `ProfileConfig` | Named | No | String | None | `export-profiles.json` under the project root |
| `SchemaReference` | Named | No | String | None | `schema-reference.json` under the project root |
| `Parallelism` | Named | No | Integer 1 through 32 | `EXPORT_PARALLELISM` | `4` |
| `ConnectionTimeoutSeconds` | Named | No | Integer 1 through 300 | `SQL_CONNECTION_TIMEOUT_SECONDS` | `30` |
| `CommandTimeoutSeconds` | Named | No | Integer 0 through 86400 | `SQL_COMMAND_TIMEOUT_SECONDS` | `0` (no timeout) |
| `Encrypt` | Switch | No | Present or absent | `SQL_ENCRYPT` | `false`, then OR with the switch |
| `TrustServerCertificate` | Switch | No | Present or absent | `SQL_TRUST_SERVER_CERTIFICATE` | `false`, then OR with the switch |
| `DryRun` | Switch | No | Present or absent | None | Off |
| `ValidateOnly` | Switch | No | Present or absent | None | Off |

Unbound integer parameters arrive as `0`. The resolver treats an integer `0` as "not supplied" and continues to the environment, `.env`, and the default. `-Parallelism 0` and `-ConnectionTimeoutSeconds 0` are already rejected by `ValidateRange`. `-CommandTimeoutSeconds 0` is valid and is also the default.

Empty strings are treated as not supplied for string parameters.

## `.env` format

`Read-DotEnv` accepts:

- Blank lines and lines whose first non-space character is `#`
- Optional `export ` prefix
- `NAME=value`
- Names that match `[A-Za-z_][A-Za-z0-9_]*`
- A matching single or double quote around the whole value

It does not expand variables, escapes, or multiline values. Unknown names are ignored by the resolver even if they parse.

Example, using placeholders only:

```text
SQL_SERVER=sql-server.example.com
SQL_DATABASE={client}
SQL_AUTHENTICATION=Sql
SQL_USER=export_user
SQL_PASSWORD=replace_me
SQL_ENCRYPT=false
SQL_TRUST_SERVER_CERTIFICATE=false
EXPORT_ROOT=./exports
EXPORT_PARALLELISM=4
SQL_CONNECTION_TIMEOUT_SECONDS=30
SQL_COMMAND_TIMEOUT_SECONDS=0
```

## Boolean environment values

`SQL_ENCRYPT` and `SQL_TRUST_SERVER_CERTIFICATE` accept `1`, `true`, `yes`, `on`, `0`, `false`, `no`, `off`, and an empty string. Empty means false. Any other text throws.

The command-line switches do not accept a false value that overrides a true environment value. The effective flag is "switch present OR environment true".

## Database name tokens

After resolution, the database name is updated with:

```powershell
$resolvedDatabase.Replace('{client}', $ClientName).Replace('{profile}', $Profile)
```

Only those exact spellings are tokens. A database name without a token is used as written.

## Profile file

`export-profiles.json` is the runtime profile file, not an example. Each profile has:

- `description`
- `excludeTablePrefixes`, a string array
- `excludeSchemas`, a string array

The script selects `profiles.<Profile>`. Adding a profile name to the JSON is not enough: `-Profile` uses `ValidateSet('standard', 'full')`. A new profile also requires a script change.

Prefix and schema comparisons are ordinal and case-insensitive. A prefix matches the start of the table name only.

## Schema reference file

`schema-reference.json` contains:

- `sourceWorkbook`, a descriptive label only. This repository does not include a workbook.
- `sourceSheet`
- `purpose`
- `tables`, a short array of synthetic table names (`Customers`, `Orders`, `OrderLines`, `Products`, and `Categories`)

Replace that list with your own table names if you want difference reporting. Do not commit a customer workbook or a real schema inventory. See [privacy-review.md](privacy-review.md). If the JSON file is absent, the export continues and skips the comparison.

## Connection string properties set by the script

These are not separate parameters:

| Property | Value |
| --- | --- |
| Data Source | Resolved server |
| Initial Catalog | Resolved database |
| Application Name | `SQL Database Exporter` |
| Connect Timeout | Resolved connection timeout |
| Encrypt | Resolved encrypt flag |
| TrustServerCertificate | Resolved trust flag |
| MultipleActiveResultSets | `false` |
| Integrated Security | `true` for `Integrated` |
| User ID and Password | SQL authentication only |

## Project root

`Get-ProjectRoot` returns the parent of the script directory when that script directory is named `src` and the parent contains `export-profiles.json`. Otherwise it returns the script directory.

`.env`, `export-profiles.json`, `schema-reference.json`, and a relative output root all use that directory. This keeps `.\data-export.ps1` and `.\src\Export-SqlDatabaseToCsv.ps1` pointed at the same files after the move into `src`.

## What is not configurable

The script does not read a general `config.json`. It does not accept a custom SQL query, an `ORDER BY`, a view list, a delimiter, an encoding switch, or a column exclude list. Those options are not implemented.
