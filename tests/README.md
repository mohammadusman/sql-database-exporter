# Tests

The automated check is `Invoke-ExporterValidation.ps1`. It runs in Windows PowerShell 5.1 and does not connect to SQL Server.

From the repository root:

```powershell
.\tests\Invoke-ExporterValidation.ps1
```

The script:

- Parses every `*.ps1` file under the repository.
- Runs `-ValidateOnly` for `standard` and `full` through `src/Export-SqlDatabaseToCsv.ps1` and through `data-export.ps1`.
- Checks that `top` without a count fails before a connection.
- Checks that an unknown profile is rejected.
- Checks that `-DryRun` fails closed when no server is configured.
- Checks the profile JSON and the synthetic schema reference.
- Checks that published text files do not contain a public Azure SQL hostname suffix.

It points `-EnvFile` at `tests/fixtures/empty.env` and clears the process copies of the SQL and export environment variables for the duration of the run. Those variables are restored afterward.

Pester 3.4.0 is the version bundled with the Windows PowerShell installation used during repository preparation. A Pester 5 suite was not added, because that version was not installed and the validation script can run without a module install. The GitHub Actions workflow runs this script and then PSScriptAnalyzer. It does not run a database integration test. No integration test is included.

Do not point a test at a production server or commit CSV output.
