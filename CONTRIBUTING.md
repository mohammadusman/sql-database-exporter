# Contributing

Thanks for considering a contribution. This project exports database tables to CSV, so changes need to preserve privacy as well as behavior.

## Report a bug

Use the bug report template. Include the PowerShell version, the export profile, and a sanitized error. Do not attach `.env`, connection strings, CSV exports, `manifest.json` from a real run, or customer data.

## Request a feature

Use the feature request template. Describe the database engine, the current behavior, and whether the change would alter CSV contents, file names, or which tables are exported.

## Submit a pull request

1. Discuss a large behavior change in an issue first.
2. Keep the existing SQL queries, profile rules, CSV formatting, and authentication order unless the change is the point of the pull request and is documented.
3. Update `README.md`, the relevant file under `docs/`, and `CHANGELOG.md` when behavior or operator instructions change.
4. Run the validation checks below.
5. Do not commit credentials, real database exports, private customer information, production manifests, or local workbooks.

## Conventions

- Target Windows PowerShell 5.1. The exporter uses `System.Data.SqlClient` from .NET Framework.
- Use approved PowerShell verbs and comment-based help for new public scripts.
- Prefer parameters, process environment variables, and an untracked `.env` file for connection settings.
- Do not write passwords, connection strings, or exported row values to the host, logs, or documentation.
- Keep examples synthetic. Use names such as `YOUR_CLIENT` and `sql-server.example.com`.
- Match the existing script style: four-space indentation and `Set-StrictMode -Version Latest` for executable scripts.

## Validation

From the repository root, in Windows PowerShell 5.1:

```powershell
.\tests\Invoke-ExporterValidation.ps1
```

The script parses every `*.ps1` file, compiles the embedded exporter with `-ValidateOnly`, and checks the profile and schema-reference files. It does not connect to a database.

If PSScriptAnalyzer is installed:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\.github\PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
```

The GitHub Actions workflow runs both checks on pull requests and on pushes to `main` or `master`. It does not run an integration test against SQL Server. No such test is included.

## Secrets and data

Do not submit:

- `.env` or any file containing a password, token, or connection string
- CSV files produced from a real database
- `exports/` output, including `manifest.json`
- Excel workbooks or other source documents that contain names, local paths, client identifiers, or tenant metadata

`.gitignore` does not remove a file that was committed earlier. If a secret is committed, rotate it and tell the maintainer. Do not try to hide it with a follow-up commit alone.
