@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive console tool: Write-Host is the intended output channel.
        'PSAvoidUsingWriteHost',
        # Requires PowerShell 7, which reads BOM-less UTF-8 correctly.
        'PSUseBOMForUnicodeEncodedFile',
        # Internal helper functions, not cmdlets exposed to callers.
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        # False positives: parameters are read from nested functions and
        # event handlers through script scope.
        'PSReviewUnusedParameter',
        # Launch history is best-effort; failing to persist it must stay silent.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
