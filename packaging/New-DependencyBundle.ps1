#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and stages pinned dependency components for the EnterpriseAI package.

.DESCRIPTION
    Reads manifest/dependencies.lock.json, downloads pinned upstream components,
    verifies SHA256 hashes, and stages them into vendor/ directories.

    This script runs ONLY during CI packaging. It must NOT run during endpoint installation.

.PARAMETER LockFilePath
    Path to dependencies.lock.json. Defaults to manifest/dependencies.lock.json relative to script root.

.PARAMETER OutputPath
    Root directory where vendor/ directories are located. Defaults to repository root.

.PARAMETER Force
    Re-download and overwrite existing vendor content.

.NOTES
    - All versions and hashes must be non-PLACEHOLDER before this script can succeed.
    - Run on GitHub Actions Windows runner during package build.
    - Internet access required during CI packaging only; not during endpoint install.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$LockFilePath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $LockFilePath) {
    $LockFilePath = Join-Path (Split-Path $ScriptRoot -Parent) 'manifest\dependencies.lock.json'
}
if (-not $OutputPath) {
    $OutputPath = Split-Path $ScriptRoot -Parent
}

function Write-Log {
    param([string]$Message, [string]$Severity = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Severity] $Message"
}

function Get-FileHashSha256 {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
}

function Invoke-DownloadWithRetry {
    param(
        [string]$Url,
        [string]$DestPath,
        [int]$MaxRetries = 3
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Log "Downloading (attempt $i): $Url"
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Url, $DestPath)
            return
        } catch {
            Write-Log "Download attempt $i failed: $($_.Exception.Message)" 'WARN'
            if ($i -eq $MaxRetries) { throw }
            Start-Sleep -Seconds (5 * $i)
        }
    }
}

try {
    Write-Log "Reading lock file: $LockFilePath"
    if (-not (Test-Path $LockFilePath)) {
        Write-Log "Lock file not found: $LockFilePath" 'ERROR'
        exit 5
    }

    $lockContent = Get-Content $LockFilePath -Raw | ConvertFrom-Json
    $deps = $lockContent.Dependencies

    # Validate no PLACEHOLDER values remain
    $props = $deps | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($depName in $props) {
        $dep = $deps.$depName
        if ($dep.Version -eq 'PLACEHOLDER' -or $dep.Sha256 -eq 'PLACEHOLDER') {
            Write-Log "Dependency '$depName' still has PLACEHOLDER values. Update dependencies.lock.json before building." 'ERROR'
            exit 5
        }
    }

    $tempDir = Join-Path $env:TEMP "EnterpriseAI-DependencyBundle-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        foreach ($depName in $props) {
            $dep = $deps.$depName
            Write-Log "Processing dependency: $depName v$($dep.Version)"

            $destDir = Join-Path $OutputPath $dep.VendorPath.Replace('/', '\')
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            $tempFile = Join-Path $tempDir $dep.ArtifactFilename

            # Download
            if ($PSCmdlet.ShouldProcess($dep.DownloadUrl, "Download $depName")) {
                Invoke-DownloadWithRetry -Url $dep.DownloadUrl -DestPath $tempFile
            }

            # Verify hash
            $actualHash = Get-FileHashSha256 -FilePath $tempFile
            $expectedHash = $dep.Sha256.ToLower()
            if ($actualHash -ne $expectedHash) {
                Write-Log "Hash mismatch for $depName! Expected: $expectedHash  Got: $actualHash" 'ERROR'
                exit 5
            }
            Write-Log "Hash verified for $depName"

            # Extract to vendor directory
            if ($PSCmdlet.ShouldProcess($destDir, "Extract $depName to vendor")) {
                # Remove old .gitkeep if present
                $gitkeep = Join-Path $destDir '.gitkeep'
                if (Test-Path $gitkeep) { Remove-Item $gitkeep -Force }

                Expand-Archive -Path $tempFile -DestinationPath $destDir -Force
                Write-Log "Staged $depName to $destDir"
            }
        }

        Write-Log "All dependencies downloaded, verified, and staged successfully."

    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    exit 0

} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
    exit 5
}
