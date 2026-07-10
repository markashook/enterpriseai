#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the EnterpriseAI release package ZIP artifact.

.DESCRIPTION
    Assembles all package components into a release ZIP archive with the standard layout:

        EnterpriseAI-LocalRuntimeGateway/
        ├── README.txt
        ├── VERSION
        ├── manifest/
        ├── config/
        ├── scripts/
        ├── vendor/
        ├── docs/
        └── packaging/mecm/

    Output filename format: EnterpriseAI-LocalRuntimeGateway-<version>-win-x64.zip

.PARAMETER RepoRoot
    Root of the repository. Defaults to two levels up from script location.

.PARAMETER OutputDir
    Directory where the ZIP artifact will be written.

.PARAMETER Version
    Package version string. Defaults to contents of VERSION file.

.PARAMETER SkipVendorCheck
    Allow building even if vendor directories are empty (for testing; not for release).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$RepoRoot,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$Version,

    [Parameter()]
    [switch]$SkipVendorCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $ScriptRoot -Parent
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot 'dist'
}

function Write-Log {
    param([string]$Message, [string]$Severity = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Severity] $Message"
}

try {
    # Determine version
    if (-not $Version) {
        $versionFile = Join-Path $RepoRoot 'VERSION'
        if (-not (Test-Path $versionFile)) {
            Write-Log "VERSION file not found: $versionFile" 'ERROR'
            exit 1
        }
        $Version = (Get-Content $versionFile -Raw).Trim()
    }
    Write-Log "Building package version: $Version"

    # Validate no PLACEHOLDER in lock file
    $lockFile = Join-Path $RepoRoot 'manifest\dependencies.lock.json'
    if (Test-Path $lockFile) {
        $lockContent = Get-Content $lockFile -Raw
        if ($lockContent -match '"PLACEHOLDER"') {
            Write-Log "dependencies.lock.json contains PLACEHOLDER values. Update all pinned versions/hashes before building a release." 'ERROR'
            exit 5
        }
    }

    # Check vendor directories (unless skipped)
    if (-not $SkipVendorCheck) {
        $vendorDirs = @('ollama', 'litellm', 'python', 'service-wrapper')
        foreach ($vdir in $vendorDirs) {
            $vpath = Join-Path $RepoRoot "vendor\$vdir"
            $items = Get-ChildItem $vpath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.gitkeep' }
            if (-not $items) {
                Write-Log "Vendor directory '$vdir' is empty. Run New-DependencyBundle.ps1 first." 'ERROR'
                exit 5
            }
        }
    }

    # Prepare staging directory
    $stagingDir = Join-Path $env:TEMP "EnterpriseAI-Build-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $packageDir = Join-Path $stagingDir 'EnterpriseAI-LocalRuntimeGateway'
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

    Write-Log "Staging package to: $packageDir"

    # Copy files to package layout
    $copyMappings = @(
        @{ Src = 'README.md';         Dst = 'README.md' }
        @{ Src = 'VERSION';           Dst = 'VERSION' }
        @{ Src = 'LICENSE';           Dst = 'LICENSE' }
        @{ Src = 'manifest';          Dst = 'manifest' }
        @{ Src = 'config';            Dst = 'config' }
        @{ Src = 'scripts';           Dst = 'scripts' }
        @{ Src = 'vendor';            Dst = 'vendor' }
        @{ Src = 'docs';              Dst = 'docs' }
        @{ Src = 'packaging\mecm';    Dst = 'packaging\mecm' }
        @{ Src = 'packaging\package-layout\README.txt'; Dst = 'README.txt' }
    )

    foreach ($mapping in $copyMappings) {
        $src = Join-Path $RepoRoot $mapping.Src
        $dst = Join-Path $packageDir $mapping.Dst
        if (-not (Test-Path $src)) {
            Write-Log "Source not found, skipping: $src" 'WARN'
            continue
        }
        if (Test-Path $src -PathType Container) {
            Copy-Item -Path $src -Destination $dst -Recurse -Force
        } else {
            $dstParent = Split-Path $dst -Parent
            if (-not (Test-Path $dstParent)) {
                New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
            }
            Copy-Item -Path $src -Destination $dst -Force
        }
    }

    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Build ZIP
    $zipName = "EnterpriseAI-LocalRuntimeGateway-$Version-win-x64.zip"
    $zipPath = Join-Path $OutputDir $zipName

    Write-Log "Creating ZIP: $zipPath"
    if ($PSCmdlet.ShouldProcess($zipPath, "Create ZIP archive")) {
        Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force
    }

    # Generate checksum
    $checksumPath = "$zipPath.sha256"
    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    "$hash  $zipName" | Set-Content -Path $checksumPath -Encoding ASCII
    Write-Log "SHA256: $hash"
    Write-Log "Checksum written: $checksumPath"

    Write-Log "Package built successfully: $zipPath"

} catch {
    Write-Log "Build failed: $($_.Exception.Message)" 'ERROR'
    exit 1
} finally {
    if ($stagingDir -and (Test-Path $stagingDir)) {
        Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
