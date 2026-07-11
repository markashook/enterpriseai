#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-EnterpriseAI.ps1'
if (-not (Test-Path -LiteralPath $testScript)) {
    Write-Error 'Test-EnterpriseAI.ps1 was not found.'
    exit 1
}

try {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $testScript, '-ConfigPath', $ConfigPath, '-OutputFormat', 'Json')
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $arguments += '-Verbose'
    }

    $jsonOutput = & powershell.exe @arguments
    $exitCode = $LASTEXITCODE

    $results = @()
    if ($jsonOutput) {
        $results = $jsonOutput | ConvertFrom-Json
    }

    $summary = [ordered]@{
        PASS = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
        WARN = @($results | Where-Object { $_.Status -eq 'WARN' }).Count
        FAIL = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
        SKIP = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
    }

    Write-Output ('EnterpriseAI post-install validation summary: PASS={0} WARN={1} FAIL={2} SKIP={3}' -f $summary.PASS, $summary.WARN, $summary.FAIL, $summary.SKIP)
    if ($results) {
        $table = $results | Select-Object @{ Name = 'Check'; Expression = { $_.Name } }, @{ Name = 'Result'; Expression = { $_.Status } }, @{ Name = 'Details'; Expression = { $_.Details } } | Format-Table -AutoSize | Out-String
        Write-Output $table.TrimEnd()
    }

    if ($exitCode -eq 0) {
        exit 0
    }
    if ($exitCode -eq 10) {
        exit 10
    }

    exit $exitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
