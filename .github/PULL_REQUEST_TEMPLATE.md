## Summary

- What changed, and why.

## Test plan

- [ ] `.\tests\Invoke-ExporterValidation.ps1` completed in Windows PowerShell 5.1.
- [ ] Documentation matches the script parameters and default paths.
- [ ] No real database export was required for this change, or the export used a disposable test database and its output was not committed.

## Privacy and security

- [ ] This pull request does not add credentials, connection strings, `.env`, CSV exports, production manifests, or client workbooks.
- [ ] Examples use synthetic values.
- [ ] New logging does not print passwords, connection strings, or row data.

## Behavior

- [ ] CSV contents, file names, profile filters, and SQL text are unchanged.
- [ ] If any of those changed, the difference is described here and in `CHANGELOG.md`.
