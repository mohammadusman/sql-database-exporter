#requires -Version 5.1

<#
.SYNOPSIS
Compatibility entry point for the SQL Server CSV exporter.

.DESCRIPTION
Forwards every argument to src/Export-SqlDatabaseToCsv.ps1. Commands that
previously called .\data-export.ps1 keep the same parameters and behavior.

Run Get-Help .\src\Export-SqlDatabaseToCsv.ps1 -Full for the parameter reference.

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT standard

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT full top 10

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly

.NOTES
The implementation resolves .env, export-profiles.json, schema-reference.json,
and the default exports directory from the repository root.
#>
$ErrorActionPreference = 'Stop'

$target = Join-Path $PSScriptRoot 'src\Export-SqlDatabaseToCsv.ps1'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Exporter script not found: $target"
}

& $target @args
