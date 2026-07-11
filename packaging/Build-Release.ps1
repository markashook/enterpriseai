#Requires -Version 5.1
<#
.SYNOPSIS
    Full release build: downloads dependencies, verifies hashes, builds package ZIP.

.DESCRIPTION
    Orchestrates the full release build process:
    1. Validates the lock file has no PLACEHOLDER values.
    2. Downloads and stages vendor components.
    3. Verifies hashes.
    4. Builds the release ZIP.

.PARAMETER RepoRoot
    Repository root directory.

.PARAMETER OutputDir
    Output directory for release artifact.

.PARAMETER Version
    Override version string.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$RepoRoot,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $ScriptRoot -Parent
}

function Write-Log {
    param([string]$Message, [string]$Severity = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Severity] $Message"
}

try {
    Write-Log "Starting release build..."

    # Step 1: Download and stage vendor dependencies
    Write-Log "Step 1: Downloading dependencies..."
    $bundleScript = Join-Path $ScriptRoot 'New-DependencyBundle.ps1'
    & $bundleScript -OutputPath $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Dependency download failed (exit $LASTEXITCODE)" 'ERROR'
        exit $LASTEXITCODE
    }

    # Step 2: Verify hashes
    Write-Log "Step 2: Verifying dependency hashes..."
    $verifyScript = Join-Path $ScriptRoot 'Verify-DependencyBundle.ps1'
    & $verifyScript -VendorRoot (Join-Path $RepoRoot 'vendor')
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Hash verification failed (exit $LASTEXITCODE)" 'ERROR'
        exit $LASTEXITCODE
    }

    # Step 3: Generate SBOM
    Write-Log "Step 3: Generating SBOM..."
    $sbomScript = Join-Path $ScriptRoot 'Generate-Sbom.ps1'
    if (Test-Path $sbomScript) {
        & $sbomScript -RepoRoot $RepoRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SBOM generation failed (exit $LASTEXITCODE)" 'WARN'
        }
    } else {
        Write-Log "SBOM generation script not found, skipping." 'WARN'
    }

    # Step 4: Build package
    Write-Log "Step 4: Building release package..."
    $buildScript = Join-Path $ScriptRoot 'Build-Package.ps1'
    $buildArgs = @{ RepoRoot = $RepoRoot }
    if ($OutputDir) { $buildArgs['OutputDir'] = $OutputDir }
    if ($Version) { $buildArgs['Version'] = $Version }
    & $buildScript @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Package build failed (exit $LASTEXITCODE)" 'ERROR'
        exit $LASTEXITCODE
    }

    Write-Log "Release build completed successfully."
    exit 0

} catch {
    Write-Log "Release build failed: $($_.Exception.Message)" 'ERROR'
    exit 1
}
