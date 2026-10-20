#requires -Version 5.1

<#
.SYNOPSIS
Exports user tables from a SQL Server database to CSV files.

.DESCRIPTION
Discovers user tables from SQL Server catalog views, applies the selected
export profile, and streams each selected table to a UTF-8 CSV file.
Tables are read concurrently. Each reader streams rows instead of loading
a whole table into memory.

Connection settings come from parameters, process environment variables,
or a local .env file, in that order. The script does not print the SQL
password. Put credentials in an untracked .env file rather than on the
command line.

This script is written for Windows PowerShell 5.1 and System.Data.SqlClient.
It uses SQL Server catalog views and T-SQL. A live database export was not
run as part of preparing this repository.

.PARAMETER ClientName
Value substituted for the {client} token and used in output file names.
This is an export label. It does not have to be a person's name.

.PARAMETER Profile
Export profile defined in export-profiles.json. Supported values are
standard and full.

.PARAMETER RowLimitKeyword
Optional positional keyword "top". When used, it must be followed by -Top
or by a positive positional record count.

.PARAMETER Top
Maximum rows to read from each selected table. SQL Server applies TOP
without an ORDER BY, so the rows are not a stable sample.

.PARAMETER ServerInstance
SQL Server instance or host. Overrides SQL_SERVER.

.PARAMETER Database
Database name. Overrides SQL_DATABASE. The tokens {client} and {profile}
are replaced after the value is resolved.

.PARAMETER Username
SQL authentication login. Overrides SQL_USER.

.PARAMETER Password
SQL authentication password. Overrides SQL_PASSWORD. Prefer .env or a
process environment variable so the password is not stored in shell history.

.PARAMETER Authentication
Sql or Integrated. Overrides SQL_AUTHENTICATION. The default is Sql.

.PARAMETER OutputRoot
Directory that will contain a timestamped run folder. Overrides EXPORT_ROOT.
Relative paths are resolved from the project root.

.PARAMETER EnvFile
Path to a .env file. The default is .env in the project root.

.PARAMETER ProfileConfig
Path to the profile JSON file. The default is export-profiles.json in the
project root.

.PARAMETER SchemaReference
Path to the optional table-name baseline. The default is schema-reference.json
in the project root. A missing file skips the comparison.

.PARAMETER Parallelism
Maximum concurrent table readers. Overrides EXPORT_PARALLELISM. The default
is 4. Valid range is 1 through 32.

.PARAMETER ConnectionTimeoutSeconds
SQL connection timeout in seconds. Overrides SQL_CONNECTION_TIMEOUT_SECONDS.
The default is 30. Valid range is 1 through 300.

.PARAMETER CommandTimeoutSeconds
SQL command timeout in seconds. Overrides SQL_COMMAND_TIMEOUT_SECONDS.
The default is 0, which means no command timeout. Valid range is 0 through
86400.

.PARAMETER Encrypt
Sets the connection Encrypt flag. Combined with SQL_ENCRYPT using OR:
the switch cannot turn encryption off when the environment value is true.

.PARAMETER TrustServerCertificate
Sets Trust Server Certificate. Combined with SQL_TRUST_SERVER_CERTIFICATE
using OR. Leave this off unless you accept the certificate risk.

.PARAMETER DryRun
Connects, discovers tables, and prints the selected tables. Does not write
CSV files.

.PARAMETER ValidateOnly
Loads the profile JSON and compiles the embedded exporter. Does not connect
to SQL Server.

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT standard

Exports every selected table for the standard profile. Connection settings
come from .env.

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT full top 10

Exports at most 10 rows from each table selected by the full profile.

.EXAMPLE
.\src\Export-SqlDatabaseToCsv.ps1 YOUR_CLIENT standard -DryRun

Lists the tables that would be exported without writing CSV files.

.EXAMPLE
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly

Checks the profile configuration and compiles the exporter without opening
a database connection.

.NOTES
The database login needs CONNECT on the database, permission to read the
catalog views used for discovery (sys.tables, sys.schemas, sys.columns,
sys.types, and sys.partitions), and SELECT on every table being exported.

CSV files can contain personal or confidential data from the source
database. Protect the output directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientName,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateSet('standard', 'full')]
    [string]$Profile,

    [Parameter(Position = 2)]
    [ValidateSet('top')]
    [string]$RowLimitKeyword,

    [Parameter(Position = 3)]
    [ValidateRange(1, 2147483647)]
    [int]$Top,

    [string]$ServerInstance,
    [string]$Database,
    [string]$Username,
    [string]$Password,

    [ValidateSet('Sql', 'Integrated')]
    [string]$Authentication,

    [string]$OutputRoot,
    [string]$EnvFile,
    [string]$ProfileConfig,
    [string]$SchemaReference,

    [ValidateRange(1, 32)]
    [int]$Parallelism,

    [ValidateRange(1, 300)]
    [int]$ConnectionTimeoutSeconds,

    [ValidateRange(0, 86400)]
    [int]$CommandTimeoutSeconds,

    [switch]$Encrypt,
    [switch]$TrustServerCertificate,
    [switch]$DryRun,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    $directory = $PSScriptRoot
    if ([string]::Equals((Split-Path -Leaf $directory), 'src', [System.StringComparison]::OrdinalIgnoreCase)) {
        $parent = Split-Path -Parent $directory
        if (Test-Path -LiteralPath (Join-Path $parent 'export-profiles.json')) {
            return $parent
        }
    }

    return $directory
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    foreach ($rawLine in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path))) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) {
            continue
        }

        if ($line.StartsWith('export ', [System.StringComparison]::OrdinalIgnoreCase)) {
            $line = $line.Substring(7).Trim()
        }

        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separator).Trim()
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            continue
        }

        $value = $line.Substring($separator + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $values[$key] = $value
    }

    return $values
}

function Resolve-Setting {
    param(
        [AllowNull()][AllowEmptyString()][object]$ParameterValue,
        [Parameter(Mandatory = $true)][string]$EnvironmentName,
        [Parameter(Mandatory = $true)][hashtable]$DotEnv,
        [AllowNull()][object]$DefaultValue
    )

    if ($null -ne $ParameterValue) {
        if ($ParameterValue -isnot [string] -or -not [string]::IsNullOrWhiteSpace([string]$ParameterValue)) {
            if ($ParameterValue -isnot [int] -or [int]$ParameterValue -ne 0) {
                return $ParameterValue
            }
        }
    }

    $environmentValue = [System.Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue
    }

    if ($DotEnv.ContainsKey($EnvironmentName) -and -not [string]::IsNullOrWhiteSpace([string]$DotEnv[$EnvironmentName])) {
        return $DotEnv[$EnvironmentName]
    }

    return $DefaultValue
}

function ConvertTo-Boolean {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    switch (([string]$Value).Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        '' { return $false }
        default { throw "$Name must be true/false, yes/no, on/off, or 1/0." }
    }
}

function Get-SafeFileComponent {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = [System.Text.RegularExpressions.Regex]::Replace($Value, '[<>:"/\\|?*\x00-\x1F]', '_')
    $safe = $safe.Trim().TrimEnd('.', ' ')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'unnamed'
    }

    $needsHash = $safe -cne $Value -or $safe.Length -gt 36
    if (-not $needsHash) {
        return $safe
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($safe))
        $hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 10).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    $prefixLength = [Math]::Min(24, $safe.Length)
    return $safe.Substring(0, $prefixLength) + '_' + $hash
}

function Test-TableExcluded {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaName,
        [Parameter(Mandatory = $true)][string]$TableName,
        [Parameter(Mandatory = $true)][object]$Rules
    )

    foreach ($schema in @($Rules.excludeSchemas)) {
        if ($SchemaName.Equals([string]$schema, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($prefix in @($Rules.excludeTablePrefixes)) {
        if ($TableName.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Add-CsvExporterType {
    if ('SqlCsvExport.SqlCsvExporter' -as [type]) {
        return
    }

    $source = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace SqlCsvExport
{
    public sealed class TableSpec
    {
        public string SchemaName { get; set; }
        public string TableName { get; set; }
        public string OutputPath { get; set; }
        public long EstimatedRows { get; set; }
    }

    public sealed class ExportResult
    {
        public string SchemaName { get; set; }
        public string TableName { get; set; }
        public string OutputPath { get; set; }
        public long EstimatedRows { get; set; }
        public long RowsExported { get; set; }
        public long BytesWritten { get; set; }
        public double DurationSeconds { get; set; }
        public bool Succeeded { get; set; }
        public string Error { get; set; }
    }

    public static class SqlCsvExporter
    {
        public static ExportResult[] ExportTables(
            string connectionString,
            TableSpec[] tables,
            int maxParallelism,
            int commandTimeoutSeconds,
            int rowLimit,
            string redactedSecret)
        {
            ConcurrentBag<ExportResult> results = new ConcurrentBag<ExportResult>();
            ParallelOptions options = new ParallelOptions();
            options.MaxDegreeOfParallelism = maxParallelism;

            Parallel.ForEach(tables, options, delegate(TableSpec table)
            {
                ExportResult result = ExportOne(connectionString, table, commandTimeoutSeconds, rowLimit, redactedSecret);
                results.Add(result);

                if (result.Succeeded)
                {
                    Console.WriteLine(
                        "[OK] [{0}].[{1}] - {2:N0} rows, {3:N1}s",
                        result.SchemaName,
                        result.TableName,
                        result.RowsExported,
                        result.DurationSeconds);
                }
                else
                {
                    Console.Error.WriteLine(
                        "[FAILED] [{0}].[{1}] - {2}",
                        result.SchemaName,
                        result.TableName,
                        result.Error);
                }
            });

            return results
                .OrderBy(r => r.SchemaName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(r => r.TableName, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        private static string SanitizeError(string message, string redactedSecret)
        {
            if (string.IsNullOrEmpty(message))
            {
                return message;
            }

            message = Regex.Replace(
                message,
                "(?i)(password\\s*=\\s*)(\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'|[^;\\r\\n]*)",
                "$1***");

            if (!string.IsNullOrEmpty(redactedSecret) &&
                redactedSecret.Length >= 8 &&
                message.IndexOf(redactedSecret, StringComparison.Ordinal) >= 0)
            {
                message = message.Replace(redactedSecret, "***");
            }

            return message;
        }

        private static ExportResult ExportOne(
            string connectionString,
            TableSpec table,
            int commandTimeoutSeconds,
            int rowLimit,
            string redactedSecret)
        {
            ExportResult result = new ExportResult();
            result.SchemaName = table.SchemaName;
            result.TableName = table.TableName;
            result.OutputPath = table.OutputPath;
            result.EstimatedRows = table.EstimatedRows;

            Stopwatch stopwatch = Stopwatch.StartNew();
            try
            {
                using (SqlConnection connection = new SqlConnection(connectionString))
                {
                    connection.Open();
                    string projection = BuildProjection(connection, table, commandTimeoutSeconds);
                    string topClause = rowLimit > 0 ? "TOP (@rowLimit) " : string.Empty;
                    string query = "SET NOCOUNT ON; SELECT " + topClause + projection + " FROM " +
                        QuoteIdentifier(table.SchemaName) + "." + QuoteIdentifier(table.TableName) + ";";

                    using (SqlCommand command = new SqlCommand(query, connection))
                    {
                        command.CommandTimeout = commandTimeoutSeconds;
                        if (rowLimit > 0)
                        {
                            command.Parameters.Add("@rowLimit", SqlDbType.Int).Value = rowLimit;
                        }
                        using (SqlDataReader reader = command.ExecuteReader(CommandBehavior.SequentialAccess))
                        using (FileStream stream = new FileStream(
                            table.OutputPath,
                            FileMode.Create,
                            FileAccess.Write,
                            FileShare.Read,
                            1048576,
                            FileOptions.SequentialScan))
                        using (StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(true), 1048576))
                        {
                            WriteHeader(writer, reader);
                            StringBuilder row = new StringBuilder(4096);

                            while (reader.Read())
                            {
                                row.Length = 0;
                                for (int index = 0; index < reader.FieldCount; index++)
                                {
                                    if (index > 0)
                                    {
                                        row.Append(',');
                                    }

                                    if (reader.IsDBNull(index))
                                    {
                                        continue;
                                    }

                                    object value = reader.GetValue(index);
                                    string text = FormatValue(value, reader.GetDataTypeName(index));
                                    AppendQuoted(row, text);
                                }
                                writer.WriteLine(row.ToString());
                                result.RowsExported++;
                            }
                        }
                    }
                }

                result.BytesWritten = new FileInfo(table.OutputPath).Length;
                result.Succeeded = true;
            }
            catch (Exception ex)
            {
                result.Error = SanitizeError(ex.GetType().Name + ": " + ex.Message, redactedSecret);
                result.Succeeded = false;
                try
                {
                    if (File.Exists(table.OutputPath))
                    {
                        File.Delete(table.OutputPath);
                    }
                }
                catch
                {
                }
            }
            finally
            {
                stopwatch.Stop();
                result.DurationSeconds = stopwatch.Elapsed.TotalSeconds;
            }

            return result;
        }

        private static string BuildProjection(
            SqlConnection connection,
            TableSpec table,
            int commandTimeoutSeconds)
        {
            const string metadataQuery = @"
SELECT c.name, ty.is_assembly_type
FROM sys.columns AS c
INNER JOIN sys.tables AS t ON t.object_id = c.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = @schemaName AND t.name = @tableName
ORDER BY c.column_id;";

            List<string> columns = new List<string>();
            using (SqlCommand metadata = new SqlCommand(metadataQuery, connection))
            {
                metadata.CommandTimeout = commandTimeoutSeconds;
                metadata.Parameters.Add("@schemaName", SqlDbType.NVarChar, 128).Value = table.SchemaName;
                metadata.Parameters.Add("@tableName", SqlDbType.NVarChar, 128).Value = table.TableName;

                using (SqlDataReader reader = metadata.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        string columnName = reader.GetString(0);
                        string quotedName = QuoteIdentifier(columnName);
                        bool isAssemblyType = reader.GetBoolean(1);
                        if (isAssemblyType)
                        {
                            columns.Add("CONVERT(varbinary(max), " + quotedName + ") AS " + quotedName);
                        }
                        else
                        {
                            columns.Add(quotedName);
                        }
                    }
                }
            }

            if (columns.Count == 0)
            {
                throw new InvalidOperationException("No columns were found for the table.");
            }

            return string.Join(", ", columns.ToArray());
        }

        private static void WriteHeader(StreamWriter writer, SqlDataReader reader)
        {
            StringBuilder header = new StringBuilder(1024);
            for (int index = 0; index < reader.FieldCount; index++)
            {
                if (index > 0)
                {
                    header.Append(',');
                }
                AppendQuoted(header, reader.GetName(index));
            }
            writer.WriteLine(header.ToString());
        }

        private static void AppendQuoted(StringBuilder target, string value)
        {
            target.Append('"');
            if (value != null)
            {
                for (int index = 0; index < value.Length; index++)
                {
                    char character = value[index];
                    if (character == '"')
                    {
                        target.Append('"');
                    }
                    target.Append(character);
                }
            }
            target.Append('"');
        }

        private static string FormatValue(object value, string sqlTypeName)
        {
            byte[] bytes = value as byte[];
            if (bytes != null)
            {
                return Convert.ToBase64String(bytes);
            }

            if (value is DateTime)
            {
                DateTime dateTime = (DateTime)value;
                if (string.Equals(sqlTypeName, "date", StringComparison.OrdinalIgnoreCase))
                {
                    return dateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                }
                return dateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffffff", CultureInfo.InvariantCulture);
            }

            if (value is DateTimeOffset)
            {
                return ((DateTimeOffset)value).ToString("o", CultureInfo.InvariantCulture);
            }

            if (value is TimeSpan)
            {
                return ((TimeSpan)value).ToString("c", CultureInfo.InvariantCulture);
            }

            if (value is double)
            {
                return ((double)value).ToString("R", CultureInfo.InvariantCulture);
            }

            if (value is float)
            {
                return ((float)value).ToString("R", CultureInfo.InvariantCulture);
            }

            IFormattable formattable = value as IFormattable;
            if (formattable != null)
            {
                return formattable.ToString(null, CultureInfo.InvariantCulture);
            }

            return Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        private static string QuoteIdentifier(string identifier)
        {
            return "[" + identifier.Replace("]", "]]" ) + "]";
        }
    }
}
'@

    Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Data.dll', 'System.Core.dll'
}

function Hide-SensitiveText {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string[]]$Secrets
    )

    if ([string]::IsNullOrEmpty($Text) -or $null -eq $Secrets) {
        return $Text
    }

    foreach ($secret in $Secrets) {
        if (-not [string]::IsNullOrEmpty($secret) -and $secret.Length -ge 8) {
            $Text = $Text.Replace($secret, '***')
        }
    }

    return $Text
}

$projectRoot = Get-ProjectRoot
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = Join-Path $projectRoot '.env'
}
if ([string]::IsNullOrWhiteSpace($ProfileConfig)) {
    $ProfileConfig = Join-Path $projectRoot 'export-profiles.json'
}
if ([string]::IsNullOrWhiteSpace($SchemaReference)) {
    $SchemaReference = Join-Path $projectRoot 'schema-reference.json'
}

$dotEnv = Read-DotEnv -Path $EnvFile

if (-not [string]::IsNullOrWhiteSpace($RowLimitKeyword) -and $Top -lt 1) {
    throw "The positional 'top' keyword must be followed by a positive record count, for example: top 10"
}

if (-not (Test-Path -LiteralPath $ProfileConfig -PathType Leaf)) {
    throw "Profile configuration not found: $ProfileConfig"
}

try {
    $profileDocument = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ProfileConfig)) | ConvertFrom-Json
    $profileProperty = $profileDocument.profiles.PSObject.Properties[$Profile]
    if ($null -eq $profileProperty) {
        throw "Profile '$Profile' was not found."
    }
    $profileRules = $profileProperty.Value
}
catch {
    throw "Unable to read profile configuration '$ProfileConfig': $($_.Exception.Message)"
}

Add-CsvExporterType

if ($ValidateOnly) {
    Write-Host "Configuration and embedded CSV exporter compiled successfully for profile '$Profile'." -ForegroundColor Green
    return
}

$resolvedServer = [string](Resolve-Setting -ParameterValue $ServerInstance -EnvironmentName 'SQL_SERVER' -DotEnv $dotEnv -DefaultValue $null)
$resolvedDatabase = [string](Resolve-Setting -ParameterValue $Database -EnvironmentName 'SQL_DATABASE' -DotEnv $dotEnv -DefaultValue '{client}')
$resolvedUsername = [string](Resolve-Setting -ParameterValue $Username -EnvironmentName 'SQL_USER' -DotEnv $dotEnv -DefaultValue $null)
$resolvedPassword = [string](Resolve-Setting -ParameterValue $Password -EnvironmentName 'SQL_PASSWORD' -DotEnv $dotEnv -DefaultValue $null)
$resolvedAuthentication = [string](Resolve-Setting -ParameterValue $Authentication -EnvironmentName 'SQL_AUTHENTICATION' -DotEnv $dotEnv -DefaultValue 'Sql')
$resolvedOutputRoot = [string](Resolve-Setting -ParameterValue $OutputRoot -EnvironmentName 'EXPORT_ROOT' -DotEnv $dotEnv -DefaultValue (Join-Path $projectRoot 'exports'))
$resolvedParallelism = [int](Resolve-Setting -ParameterValue $Parallelism -EnvironmentName 'EXPORT_PARALLELISM' -DotEnv $dotEnv -DefaultValue 4)
$resolvedConnectionTimeout = [int](Resolve-Setting -ParameterValue $ConnectionTimeoutSeconds -EnvironmentName 'SQL_CONNECTION_TIMEOUT_SECONDS' -DotEnv $dotEnv -DefaultValue 30)
$resolvedCommandTimeout = [int](Resolve-Setting -ParameterValue $CommandTimeoutSeconds -EnvironmentName 'SQL_COMMAND_TIMEOUT_SECONDS' -DotEnv $dotEnv -DefaultValue 0)

$envEncrypt = ConvertTo-Boolean -Value (Resolve-Setting -ParameterValue $null -EnvironmentName 'SQL_ENCRYPT' -DotEnv $dotEnv -DefaultValue $false) -Name 'SQL_ENCRYPT'
$envTrustCertificate = ConvertTo-Boolean -Value (Resolve-Setting -ParameterValue $null -EnvironmentName 'SQL_TRUST_SERVER_CERTIFICATE' -DotEnv $dotEnv -DefaultValue $false) -Name 'SQL_TRUST_SERVER_CERTIFICATE'
$resolvedEncrypt = $Encrypt.IsPresent -or $envEncrypt
$resolvedTrustCertificate = $TrustServerCertificate.IsPresent -or $envTrustCertificate

if ([string]::IsNullOrWhiteSpace($resolvedServer)) {
    throw 'SQL server is required. Set SQL_SERVER in .env or pass -ServerInstance.'
}

$resolvedDatabase = $resolvedDatabase.Replace('{client}', $ClientName).Replace('{profile}', $Profile)
if ([string]::IsNullOrWhiteSpace($resolvedDatabase)) {
    throw 'SQL database is required. Set SQL_DATABASE in .env or pass -Database.'
}

if ($resolvedAuthentication -notin @('Sql', 'Integrated')) {
    throw "SQL_AUTHENTICATION must be 'Sql' or 'Integrated'."
}

if ($resolvedAuthentication -eq 'Sql' -and
    ([string]::IsNullOrWhiteSpace($resolvedUsername) -or [string]::IsNullOrWhiteSpace($resolvedPassword))) {
    throw 'SQL authentication requires SQL_USER and SQL_PASSWORD in .env, or -Username and -Password.'
}

if ($resolvedParallelism -lt 1 -or $resolvedParallelism -gt 32) {
    throw 'EXPORT_PARALLELISM must be between 1 and 32.'
}

if ($resolvedConnectionTimeout -lt 1 -or $resolvedConnectionTimeout -gt 300) {
    throw 'SQL_CONNECTION_TIMEOUT_SECONDS must be between 1 and 300.'
}

if ($resolvedCommandTimeout -lt 0 -or $resolvedCommandTimeout -gt 86400) {
    throw 'SQL_COMMAND_TIMEOUT_SECONDS must be between 0 and 86400. Use 0 for no timeout.'
}

$connectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$connectionBuilder['Data Source'] = $resolvedServer
$connectionBuilder['Initial Catalog'] = $resolvedDatabase
$connectionBuilder['Application Name'] = 'SQL Database Exporter'
$connectionBuilder['Connect Timeout'] = $resolvedConnectionTimeout
$connectionBuilder['Encrypt'] = $resolvedEncrypt
$connectionBuilder['TrustServerCertificate'] = $resolvedTrustCertificate
$connectionBuilder['MultipleActiveResultSets'] = $false

if ($resolvedAuthentication -eq 'Integrated') {
    $connectionBuilder['Integrated Security'] = $true
}
else {
    $connectionBuilder['User ID'] = $resolvedUsername
    $connectionBuilder['Password'] = $resolvedPassword
}

$catalogQuery = @'
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    COALESCE(SUM(CASE WHEN p.index_id IN (0, 1) THEN p.[rows] ELSE 0 END), 0) AS EstimatedRows
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.partitions AS p ON p.object_id = t.object_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
ORDER BY EstimatedRows DESC, s.name, t.name;
'@

$discoveredTables = New-Object System.Collections.Generic.List[object]
$connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList (, $connectionBuilder.ConnectionString)
$command = $null
$reader = $null
try {
    Write-Host "Connecting to '$resolvedServer' / '$resolvedDatabase'..."
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $catalogQuery
    $command.CommandTimeout = $resolvedCommandTimeout
    $reader = $command.ExecuteReader()
    while ($reader.Read()) {
        $discoveredTables.Add([pscustomobject]@{
            SchemaName = $reader.GetString(0)
            TableName = $reader.GetString(1)
            EstimatedRows = $reader.GetInt64(2)
        })
    }
}
finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }
    if ($null -ne $command) {
        $command.Dispose()
    }
    $connection.Dispose()
}

$selectedTables = @()
$excludedTables = @()
foreach ($table in $discoveredTables) {
    if (Test-TableExcluded -SchemaName $table.SchemaName -TableName $table.TableName -Rules $profileRules) {
        $excludedTables += $table
    }
    else {
        $selectedTables += $table
    }
}

if ($selectedTables.Count -eq 0) {
    throw "No tables matched profile '$Profile' in database '$resolvedDatabase'."
}

$referenceComparison = $null
if (Test-Path -LiteralPath $SchemaReference -PathType Leaf) {
    try {
        $referenceDocument = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $SchemaReference)) | ConvertFrom-Json
        $referenceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($referenceDocument.tables)) {
            [void]$referenceSet.Add([string]$name)
        }

        $actualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($table in $discoveredTables) {
            [void]$actualSet.Add([string]$table.TableName)
        }

        $additional = @($actualSet | Where-Object { -not $referenceSet.Contains($_) } | Sort-Object)
        $missing = @($referenceSet | Where-Object { -not $actualSet.Contains($_) } | Sort-Object)
        $referenceComparison = [ordered]@{
            ReferenceTableCount = $referenceSet.Count
            AdditionalDatabaseTables = $additional
            MissingReferenceTables = $missing
        }
    }
    catch {
        Write-Warning "Schema reference could not be compared: $($_.Exception.Message)"
    }
}

$limitDescription = if ($Top -gt 0) { "top $Top rows per table" } else { 'all rows' }
Write-Host ("Discovered {0} user tables; selected {1}; excluded {2} for profile '{3}'; exporting {4}." -f $discoveredTables.Count, $selectedTables.Count, $excludedTables.Count, $Profile, $limitDescription)

if ($DryRun) {
    foreach ($table in $selectedTables) {
        Write-Output ("{0}.{1} ({2:N0} estimated rows)" -f $table.SchemaName, $table.TableName, $table.EstimatedRows)
    }
    return
}

$safeClient = Get-SafeFileComponent -Value $ClientName
$safeProfile = Get-SafeFileComponent -Value $Profile
$runStamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')
$dateStamp = [DateTime]::UtcNow.ToString('yyyyMMdd')

if (-not [System.IO.Path]::IsPathRooted($resolvedOutputRoot)) {
    $resolvedOutputRoot = Join-Path $projectRoot $resolvedOutputRoot
}

$runDirectory = Join-Path $resolvedOutputRoot ("{0}_{1}_{2}" -f $safeClient, $safeProfile, $runStamp)
[void](New-Item -ItemType Directory -Force -Path $runDirectory)

[SqlCsvExport.TableSpec[]]$tableSpecs = @(
    foreach ($table in $selectedTables) {
        $safeSchema = Get-SafeFileComponent -Value $table.SchemaName
        $safeTable = Get-SafeFileComponent -Value $table.TableName
        $schemaPart = if ($table.SchemaName.Equals('dbo', [System.StringComparison]::OrdinalIgnoreCase)) { '' } else { $safeSchema + '_' }
        $fileName = "${safeClient}_${schemaPart}${safeTable}_${dateStamp}.csv"

        $spec = New-Object SqlCsvExport.TableSpec
        $spec.SchemaName = $table.SchemaName
        $spec.TableName = $table.TableName
        $spec.EstimatedRows = $table.EstimatedRows
        $spec.OutputPath = Join-Path $runDirectory $fileName
        $spec
    }
)

$startedUtc = [DateTime]::UtcNow
$redactedSecret = if ($resolvedPassword.Length -ge 8) { $resolvedPassword } else { $null }
Write-Host "Exporting $($tableSpecs.Count) tables with $resolvedParallelism parallel readers to '$runDirectory'..."
$results = [SqlCsvExport.SqlCsvExporter]::ExportTables(
    $connectionBuilder.ConnectionString,
    $tableSpecs,
    $resolvedParallelism,
    $resolvedCommandTimeout,
    $Top,
    $redactedSecret)
$finishedUtc = [DateTime]::UtcNow

foreach ($result in @($results)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
        $result.Error = Hide-SensitiveText -Text ([string]$result.Error) -Secrets @($redactedSecret)
    }
}

$succeeded = @($results | Where-Object { $_.Succeeded })
$failed = @($results | Where-Object { -not $_.Succeeded })
$totalRows = ($succeeded | Measure-Object -Property RowsExported -Sum).Sum
$totalBytes = ($succeeded | Measure-Object -Property BytesWritten -Sum).Sum
if ($null -eq $totalRows) { $totalRows = 0 }
if ($null -eq $totalBytes) { $totalBytes = 0 }

$manifest = [ordered]@{
    ClientName = $ClientName
    Profile = $Profile
    Server = $resolvedServer
    Database = $resolvedDatabase
    StartedUtc = $startedUtc.ToString('o')
    FinishedUtc = $finishedUtc.ToString('o')
    DurationSeconds = [Math]::Round(($finishedUtc - $startedUtc).TotalSeconds, 3)
    Parallelism = $resolvedParallelism
    RowLimitPerTable = if ($Top -gt 0) { $Top } else { $null }
    Filters = [ordered]@{
        ExcludeTablePrefixes = @($profileRules.excludeTablePrefixes)
        ExcludeSchemas = @($profileRules.excludeSchemas)
    }
    Summary = [ordered]@{
        DiscoveredTables = $discoveredTables.Count
        SelectedTables = $selectedTables.Count
        ExcludedTables = $excludedTables.Count
        SucceededTables = $succeeded.Count
        FailedTables = $failed.Count
        RowsExported = [long]$totalRows
        BytesWritten = [long]$totalBytes
    }
    ExcludedObjects = @($excludedTables | ForEach-Object { "[$($_.SchemaName)].[$($_.TableName)]" })
    SchemaReferenceComparison = $referenceComparison
    Tables = @($results | ForEach-Object {
        [ordered]@{
            Schema = $_.SchemaName
            Table = $_.TableName
            File = if ($_.Succeeded) { [System.IO.Path]::GetFileName($_.OutputPath) } else { $null }
            EstimatedRows = $_.EstimatedRows
            RowsExported = $_.RowsExported
            BytesWritten = $_.BytesWritten
            DurationSeconds = [Math]::Round($_.DurationSeconds, 3)
            Succeeded = $_.Succeeded
            Error = $_.Error
        }
    })
}

$manifestPath = Join-Path $runDirectory 'manifest.json'
$manifestJson = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("Completed: {0}/{1} tables, {2:N0} rows, {3:N2} MB." -f $succeeded.Count, $results.Count, $totalRows, ($totalBytes / 1MB)) -ForegroundColor Green
Write-Host "Manifest: $manifestPath"

if ($failed.Count -gt 0) {
    throw "$($failed.Count) table export(s) failed. See '$manifestPath' for details."
}
