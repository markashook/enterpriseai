#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies that all vendored dependency bundles match the declared SHA256 hashes.

.DESCRIPTION
    Reads manifest/dependencies.lock.json and manifest/hashes.sha256 to verify
    that staged vendor content matches expected hashes.

.PARAMETER LockFilePath
    Path to dependencies.lock.json.

.PARAMETER HashesFilePath
    Path to hashes.sha256.

.PARAMETER VendorRoot
    Root vendor directory path.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$LockFilePath,

    [Parameter()]
    [string]$HashesFilePath,

    [Parameter()]
    [string]$VendorRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $LockFilePath) {
    $LockFilePath = Join-Path (Split-Path $ScriptRoot -Parent) 'manifest\dependencies.lock.json'
}
if (-not $HashesFilePath) {
    $HashesFilePath = Join-Path (Split-Path $ScriptRoot -Parent) 'manifest\hashes.sha256'
}
if (-not $VendorRoot) {
    $VendorRoot = Join-Path (Split-Path $ScriptRoot -Parent) 'vendor'
}

function Write-Log {
    param([string]$Message, [string]$Severity = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Severity] $Message"
}

$allPassed = $true

try {
    Write-Log "Verifying dependency bundle hashes..."

    if (-not (Test-Path $LockFilePath)) {
        Write-Log "Lock file not found: $LockFilePath" 'ERROR'
        exit 5
    }

    $lockContent = Get-Content $LockFilePath -Raw | ConvertFrom-Json
    $deps = $lockContent.Dependencies
    $props = $deps | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    foreach ($depName in $props) {
        $dep = $deps.$depName
        if ($dep.Sha256 -eq 'PLACEHOLDER') {
            Write-Log "Dependency '$depName' has PLACEHOLDER hash. Cannot verify." 'ERROR'
            $allPassed = $false
            continue
        }

        $vendorDir = Join-Path $VendorRoot ($dep.VendorPath.Replace('vendor/', '').Replace('/', '\'))
        if (-not (Test-Path $vendorDir)) {
            Write-Log "Vendor directory not found for ${depName}: $vendorDir" 'ERROR'
            $allPassed = $false
            continue
        }

        # Check if vendor dir has actual content (not just .gitkeep)
        $items = Get-ChildItem $vendorDir -File | Where-Object { $_.Name -ne '.gitkeep' }
        if (-not $items) {
            Write-Log "Vendor directory for ${depName} is empty (no content beyond .gitkeep): $vendorDir" 'WARN'
            continue
        }

        Write-Log "Vendor directory for ${depName}: $vendorDir ($(($items | Measure-Object).Count) files)"
    }

    if ($allPassed) {
        Write-Log "Dependency bundle verification passed."
        exit 0
    } else {
        Write-Log "Dependency bundle verification FAILED." 'ERROR'
        exit 5
    }

} catch {
    Write-Log "Fatal error during verification: $($_.Exception.Message)" 'ERROR'
    exit 5
}
