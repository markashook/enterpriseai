#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packageRoot = Split-Path -Path $PSScriptRoot -Parent
$configPath = Join-Path -Path $packageRoot -ChildPath 'config\enterpriseai.package.json'
$versionPath = Join-Path -Path $packageRoot -ChildPath 'VERSION'
$registryKey = 'HKLM:\Software\EnterpriseAI\LocalRuntimeGateway'
$installRoot = 'C:\Program Files\EnterpriseAI'
$programDataRoot = 'C:\ProgramData\EnterpriseAI'
$ollamaService = 'EnterpriseAI-Ollama'
$litellmService = 'EnterpriseAI-LiteLLM'

try {
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        if ($config.RegistryKey) { $registryKey = [string]$config.RegistryKey }
        if ($config.InstallRoot) { $installRoot = [string]$config.InstallRoot }
        if ($config.ProgramDataRoot) { $programDataRoot = [string]$config.ProgramDataRoot }
        if ($config.OllamaServiceName) { $ollamaService = [string]$config.OllamaServiceName }
        if ($config.LiteLLMServiceName) { $litellmService = [string]$config.LiteLLMServiceName }
    }

    if (-not (Test-Path -LiteralPath $registryKey)) { exit 1 }
    if (-not (Test-Path -LiteralPath $versionPath)) { exit 1 }

    $expectedVersion = (Get-Content -Path $versionPath | Select-Object -First 1).Trim()
    $registryVersion = (Get-ItemProperty -Path $registryKey -Name PackageVersion -ErrorAction Stop).PackageVersion
    if ($registryVersion -ne $expectedVersion) { exit 1 }

    if (-not (Get-Service -Name $ollamaService -ErrorAction SilentlyContinue)) { exit 1 }
    if (-not (Get-Service -Name $litellmService -ErrorAction SilentlyContinue)) { exit 1 }
    if (-not (Test-Path -LiteralPath $installRoot)) { exit 1 }
    if (-not (Test-Path -LiteralPath $programDataRoot)) { exit 1 }

    Write-Output 'Installed'
    exit 0
}
catch {
    exit 1
}
