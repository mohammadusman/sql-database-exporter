#requires -Version 5.1

<#
.SYNOPSIS
Validates the exporter without connecting to SQL Server.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$implementation = Join-Path $root 'src\Export-SqlDatabaseToCsv.ps1'
$wrapper = Join-Path $root 'data-export.ps1'
$emptyEnv = Join-Path $PSScriptRoot 'fixtures\empty.env'
$environmentNames = @(
    'SQL_SERVER',
    'SQL_DATABASE',
    'SQL_USER',
    'SQL_PASSWORD',
    'SQL_AUTHENTICATION',
    'EXPORT_ROOT',
    'EXPORT_PARALLELISM',
    'SQL_CONNECTION_TIMEOUT_SECONDS',
    'SQL_COMMAND_TIMEOUT_SECONDS',
    'SQL_ENCRYPT',
    'SQL_TRUST_SERVER_CERTIFICATE'
)

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ThrowsMatching {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Script,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $threw = $false
    try {
        & $Script
    }
    catch {
        $threw = $true
        $text = $_.Exception.Message
        if ($text -notmatch $Pattern) {
            throw "$Message The exception did not match the expected pattern."
        }
    }

    if (-not $threw) {
        throw $Message
    }
}

$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
}

try {
    $scripts = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File)
    Assert-Condition ($scripts.Count -ge 3) 'Expected the wrapper, implementation, and validation script.'

    foreach ($file in $scripts) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and @($parseErrors).Count -gt 0) {
            $details = @($parseErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "PowerShell parse error in $($file.FullName): $details"
        }
    }

    & $implementation 'example-client' 'standard' -ValidateOnly -EnvFile $emptyEnv
    & $implementation 'example-client' 'full' -ValidateOnly -EnvFile $emptyEnv
    & $wrapper 'example-client' 'standard' -ValidateOnly -EnvFile $emptyEnv

    Assert-ThrowsMatching -Pattern 'positive record count' -Message 'top without a count must fail.' -Script {
        & $implementation 'example-client' 'standard' 'top' -EnvFile $emptyEnv
    }

    Assert-ThrowsMatching -Pattern 'Profile' -Message 'An unknown profile must fail.' -Script {
        & $implementation 'example-client' 'unknown-profile' -ValidateOnly -EnvFile $emptyEnv
    }

    Assert-ThrowsMatching -Pattern 'SQL server is required' -Message 'DryRun without a server must fail before connecting.' -Script {
        & $implementation 'example-client' 'standard' -DryRun -EnvFile $emptyEnv
    }

    $profiles = Get-Content -LiteralPath (Join-Path $root 'export-profiles.json') -Raw | ConvertFrom-Json
    Assert-Condition ($null -ne $profiles.profiles.standard) 'The standard profile is missing.'
    Assert-Condition ($null -ne $profiles.profiles.full) 'The full profile is missing.'
    Assert-Condition (@($profiles.profiles.standard.excludeSchemas) -contains 'audit') 'standard must exclude the audit schema.'
    Assert-Condition (@($profiles.profiles.standard.excludeSchemas) -contains 'staging') 'standard must exclude the staging schema.'
    Assert-Condition (@($profiles.profiles.full.excludeSchemas) -contains 'audit') 'full must exclude the audit schema.'
    Assert-Condition (@($profiles.profiles.full.excludeSchemas) -notcontains 'staging') 'full must not exclude the staging schema.'

    $reference = Get-Content -LiteralPath (Join-Path $root 'schema-reference.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($reference.tables).Count -eq 5) 'schema-reference.json no longer has the five synthetic table names.'
    Assert-Condition (@($reference.tables) -contains 'Customers') 'schema-reference.json is missing the synthetic Customers table.'

    $help = Get-Help -Name $implementation -Full
    Assert-Condition ($help.Synopsis -match 'CSV') 'The implementation comment-based help is missing its synopsis.'

    $ignoredPatterns = Get-Content -LiteralPath (Join-Path $root '.gitignore')
    foreach ($requiredPattern in @('.env', 'exports/', '*.csv', '*.xlsx')) {
        Assert-Condition (@($ignoredPatterns) -contains $requiredPattern) ".gitignore is missing $requiredPattern."
    }

    $publishedFiles = Get-ChildItem -LiteralPath $root -Recurse -File -Force |
        Where-Object {
            $_.Name -ne '.env' -and
            $_.Extension -notin @('.xlsx', '.xls') -and
            $_.FullName -notmatch '\\exports\\'
        }

    $forbiddenMatches = @($publishedFiles | Select-String -Pattern 'database\.windows\.net' -AllMatches)
    if ($forbiddenMatches.Count -gt 0) {
        $paths = @($forbiddenMatches | ForEach-Object { $_.Path } | Select-Object -Unique) -join ', '
        throw "Remove cloud SQL host names from files intended for publication: $paths"
    }
}
finally {
    foreach ($name in $environmentNames) {
        $previous = $savedEnvironment[$name]
        if ([string]::IsNullOrEmpty($previous)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -Path "Env:$name" -Value $previous
        }
    }
}

Write-Output 'Exporter validation passed.'
