# Troubleshooting

Verified behavior comes from the script. Recommendations are general operator guidance and are marked as such.

## Authentication failed

Verified: SQL authentication throws, before a catalog query, when `SQL_USER` or `SQL_PASSWORD` is empty: `SQL authentication requires SQL_USER and SQL_PASSWORD in .env, or -Username and -Password.`

Verified: `SQL_AUTHENTICATION` must be `Sql` or `Integrated`. Any other value throws.

A later failure from SQL Server, such as a rejected login, is a provider exception. The message is printed with the table export or connection error. The script removes `Password=` segments and, when the password is at least 8 characters, the password text itself. Login names can still appear in provider messages. Remove them before you share an error.

Recommendation: confirm the login, the database, and whether the server allows SQL authentication. Prefer a dedicated export login. Rotate a password that was typed into a command line or committed.

## Connection and network problems

Verified: an empty server throws `SQL server is required. Set SQL_SERVER in .env or pass -ServerInstance.` The script prints `Connecting to '<server>' / '<database>'...` before `Open()`. That line does not include the user or password.

Verified: `SQL_CONNECTION_TIMEOUT_SECONDS` and `-ConnectionTimeoutSeconds` accept 1 through 300. The connection string property is `Connect Timeout`.

Verified: `Encrypt` defaults to false unless `SQL_ENCRYPT` is true or `-Encrypt` is present. A server that requires encryption can reject a connection when the flag is false. Set `SQL_ENCRYPT=true` in `.env` and run again. This default was not changed, because changing it would change existing connection behavior.

Recommendation: check DNS, firewalls, and the instance name. For a named instance, use the server string you already use with other SQL Server clients. No live connection was attempted while preparing this repository.

## Insufficient permissions

Verified: discovery queries `sys.tables`, `sys.schemas`, and `sys.partitions`. Column projection queries `sys.columns`, `sys.tables`, `sys.schemas`, and `sys.types`. The data query is `SELECT` on the table. A permission error on one table is stored as that table's error. Other tables continue. The process throws at the end with the manifest path.

Recommendation: grant `CONNECT`, `SELECT` on the exported tables, and enough catalog visibility to see those tables. If discovery returns no rows, the login may not be allowed to see metadata. The script then throws `No tables matched profile '<profile>' in database '<database>'.` That message does not distinguish "the database has no user tables" from "the login cannot see them".

## Missing modules or drivers

Verified: the script does not import the `SqlServer` module. `-ValidateOnly` compiles the embedded C# with `System.Data.dll` and `System.Core.dll`.

If `Add-Type` fails, Windows PowerShell 5.1 is not the host, or .NET Framework's `System.Data` assembly is unavailable. Run `$PSVersionTable` and use Windows PowerShell rather than PowerShell 7 unless you have separately verified the compile there. PowerShell 7 was not installed in the review environment.

## Profile and parameter errors

Verified:

- `-Profile` only accepts `standard` and `full`.
- A missing profile file throws `Profile configuration not found`.
- Invalid JSON, or a missing profile property, throws `Unable to read profile configuration`.
- `top` without a positive count throws before connecting.
- `-ValidateOnly` returns after a successful compile and does not open SQL Server.

## CSV encoding or delimiter issues

Verified: files are UTF-8 with a BOM, comma-delimited, with quoting implemented in the embedded exporter. Null database values become empty unquoted fields. A consumer that treats every field as quoted can misread nulls. There is no delimiter parameter.

Binary and assembly-typed values become Base64 text, not raw bytes. Date values are invariant-culture strings, not the local regional format.

Recommendation: open the CSV in a tool that understands UTF-8 and RFC-style doubled quotes. Excel may still reinterpret date columns and large numbers. Compare a small `-Top` export with a known row before loading a full run.

## File access and output directory errors

Verified: the script creates the run directory with `New-Item -ItemType Directory -Force`. CSV files are created with `FileMode.Create`. A failure while writing a table attempts to delete that file. The manifest is written with `File.WriteAllText` after the table loop.

Relative output paths are combined with the project root, not with the caller's current directory.

Recommendation: confirm the account can create directories and files under the output root, and that the disk has room for the largest tables. Two sanitized names that collide use the same path; the later file replaces the earlier one. The manifest still lists both table results.

## Large exports, memory, and timeouts

Verified:

- Each reader uses `CommandBehavior.SequentialAccess` and writes through a 1 MB buffer.
- Up to `Parallelism` tables are read at once. The default is 4.
- The command timeout defaults to 0, which is unlimited.
- Estimated sizes printed by `-DryRun` come from `sys.partitions` and can be wrong.
- Tables are not read inside one transaction or snapshot.

Recommendation: start with `-DryRun`, then `-Top 10`, then a full export of a restored backup. Increase parallelism only after the server has capacity. Set `-CommandTimeoutSeconds` to a finite value if you would rather fail a stuck query than wait. Streaming lowers client memory compared with loading a table at once; it does not reduce the size of the CSV on disk or the load on SQL Server.

## Schema reference warnings

Verified: a missing `schema-reference.json` skips the comparison. A file that cannot be parsed produces the warning `Schema reference could not be compared` and the export continues. The comparison uses table names only.

## Sharing an error

Remove the server, database, login, and any row values before posting an error. Do not attach `exports` or `.env`. If a message still contains a secret, rotate that secret.
