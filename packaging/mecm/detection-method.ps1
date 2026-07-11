#Requires -Version 5.1
<#
.SYNOPSIS
    MECM/SCCM detection method for EnterpriseAI Local Runtime and Gateway.

.DESCRIPTION
    This script is used as the MECM/SCCM detection method for the EnterpriseAI application.
    It checks whether the package is correctly installed by verifying:
    - Registry key and version
    - Services exist
    - Install root and ProgramData root exist

    Per MECM convention:
    - If the application IS installed: output a value (e.g., "Installed") and exit 0.
    - If the application is NOT installed: output nothing and exit 0 (or exit 1 for error).
    - MECM interprets any output + exit 0 as "detected".

.NOTES
    Run by MECM/SCCM in the context of the deploying user or system account.
    Do not write to log files from this script; it must be silent on non-detection.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RegistryKey = 'HKLM:\Software\EnterpriseAI\LocalRuntimeGateway'
$ExpectedInstallRoot = 'C:\Program Files\EnterpriseAI'
$ExpectedProgramDataRoot = 'C:\ProgramData\EnterpriseAI'
$OllamaServiceName = 'EnterpriseAI-Ollama'
$LiteLLMServiceName = 'EnterpriseAI-LiteLLM'
$VersionFile = Join-Path $ExpectedInstallRoot 'VERSION'

function Get-ExpectedVersion {
    # Read expected version from registry or VERSION file
    try {
        if (Test-Path $RegistryKey) {
            $val = (Get-ItemProperty -Path $RegistryKey -ErrorAction SilentlyContinue).PackageVersion
            if ($val) { return $val }
        }
    } catch { }
    return $null
}

try {
    # 1. Check registry key exists
    if (-not (Test-Path $RegistryKey)) {
        exit 0
    }

    # 2. Check PackageVersion value exists
    $regProps = Get-ItemProperty -Path $RegistryKey -ErrorAction SilentlyContinue
    if (-not $regProps -or -not $regProps.PackageVersion) {
        exit 0
    }

    # 3. Check VERSION file exists and matches registry
    if (-not (Test-Path $VersionFile)) {
        exit 0
    }
    $fileVersion = (Get-Content $VersionFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($fileVersion -ne $regProps.PackageVersion) {
        exit 0
    }

    # 4. Check Ollama service exists
    $ollamaService = Get-Service -Name $OllamaServiceName -ErrorAction SilentlyContinue
    if (-not $ollamaService) {
        exit 0
    }

    # 5. Check LiteLLM service exists
    $litellmService = Get-Service -Name $LiteLLMServiceName -ErrorAction SilentlyContinue
    if (-not $litellmService) {
        exit 0
    }

    # 6. Check install root directory exists
    if (-not (Test-Path $ExpectedInstallRoot -PathType Container)) {
        exit 0
    }

    # 7. Check ProgramData root directory exists
    if (-not (Test-Path $ExpectedProgramDataRoot -PathType Container)) {
        exit 0
    }

    # All checks passed - output detected value and exit 0
    Write-Output "Installed"
    exit 0

} catch {
    # Unexpected error during detection - do not output anything
    exit 1
}
