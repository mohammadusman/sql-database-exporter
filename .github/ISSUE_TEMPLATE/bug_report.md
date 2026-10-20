---
name: Bug report
about: Report a defect in the SQL Server CSV exporter
title: ''
labels: ''
---

## What happened

## What you expected

## How to reproduce

Use synthetic names. Do not paste a `.env` file, a password, a connection string, or rows from an export.

```powershell
.\data-export.ps1 YOUR_CLIENT standard -ValidateOnly
```

## Environment

- Windows PowerShell version (`$PSVersionTable.PSVersion`):
- Operating system:
- SQL Server or Azure SQL version, if known and safe to share:
- Profile (`standard` or `full`):
- Authentication (`Sql` or `Integrated`):

## Sanitized error

Remove server names, database names, user names, and any data values.

```text

```

## Confirmation

- [ ] I did not attach CSV files, `manifest.json`, `.env`, or a database backup.
