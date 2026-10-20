# Installation

## Supported environment

This was reviewed on Windows PowerShell 5.1 (`$PSVersionTable.PSEdition` = `Desktop`) on Windows.

| Requirement | Status in this repository |
| --- | --- |
| Windows PowerShell 5.1 | Required by `#requires -Version 5.1` and by `System.Data.SqlClient` |
| PowerShell 7 | Not installed during review. Not claimed as supported |
| Microsoft SQL Server | The script uses T-SQL, `sys` catalog views, and `System.Data.SqlClient` |
| Azure SQL Database | Uses a similar client and T-SQL surface, but no connection was made during review, so compatibility is not verified |
| `SqlServer` PowerShell module | Not used |
| Internet access at runtime | Not required, except for the network path to your SQL Server |

The embedded exporter is compiled in the Windows PowerShell process with:

```powershell
Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Data.dll', 'System.Core.dll'
```

`System.Data.SqlClient` comes from that .NET Framework assembly. There is no NuGet package or module to install for the export itself.

## Setup

1. Install Windows PowerShell 5.1 if the machine does not already have it. It is included with supported Windows versions that still ship Windows PowerShell.
2. Copy this repository to the machine that will run the export.
3. Open Windows PowerShell. The script was not validated in PowerShell 7.
4. From the repository root, create a local environment file:

```powershell
Copy-Item .env.example .env
```

5. Edit `.env`. Replace `sql-server.example.com`, `export_user`, and `replace_me` with values for a database you are authorized to read. Leave `.env` untracked.
6. Confirm the configuration compiles without connecting:

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly
```

Expected host output includes: configuration and embedded CSV exporter compiled successfully.

## Database permissions

The script runs the statements below. Grant only what those statements need.

Discovery:

```sql
SELECT s.name, t.name, partition row estimates
FROM sys.tables
INNER JOIN sys.schemas
LEFT JOIN sys.partitions
WHERE t.is_ms_shipped = 0
```

Column list, per table:

```sql
SELECT c.name, ty.is_assembly_type
FROM sys.columns
INNER JOIN sys.tables
INNER JOIN sys.schemas
INNER JOIN sys.types
```

Data export, per selected table:

```sql
SELECT columns FROM [schema].[table]
```

The login therefore needs:

- `CONNECT` on the target database.
- Permission to read the catalog rows used above for every table that should be discovered. On SQL Server, metadata visibility usually follows the caller's permissions on the underlying object. Some environments also require `VIEW DEFINITION`. This repository does not include a tested permission script.
- `SELECT` on every table the profile will export.

The profile exclusions are applied after discovery. A login that can see a table can still cause it to be considered before the profile drops it. Use a login that cannot read schemas you do not want to export if that separation matters.

The export does not insert, update, delete, or alter objects. It still copies the data it can select. A read-only login is appropriate.

## Files the script expects

| File | Role |
| --- | --- |
| `data-export.ps1` | Compatibility entry point |
| `src/Export-SqlDatabaseToCsv.ps1` | Implementation |
| `export-profiles.json` | Required profile rules, unless `-ProfileConfig` points elsewhere |
| `schema-reference.json` | Optional comparison baseline |
| `.env` | Optional local settings. Ignored by Git |

When the implementation lives in `src` and `export-profiles.json` is in the parent directory, those defaults resolve from the repository root. A copy of the script that is not in a `src` directory resolves them from the script's own directory, which is the previous layout.

## Next step

[Usage](usage.md) covers the export commands and the output layout.
