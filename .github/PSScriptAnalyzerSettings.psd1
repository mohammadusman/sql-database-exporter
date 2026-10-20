@{
    Severity = @('Error', 'Warning')
    # The password is a string because SqlConnectionStringBuilder and the
    # .env file both use a plaintext value. Do not log that value.
    # Write-Host is the existing progress channel for operators.
    ExcludeRules = @(
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingWriteHost'
    )
}
