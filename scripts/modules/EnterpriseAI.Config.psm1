#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:EAIRequiredConfigFields = @(
    'PackageName',
    'PackageShortName',
    'InstallRoot',
    'ProgramDataRoot',
    'ServiceAccountName',
    'OllamaServiceName',
    'LiteLLMServiceName',
    'OllamaEndpoint',
    'LiteLLMEndpoint',
    'FirewallRulePrefix'
)

function Get-EAIConfigPath {
    [CmdletBinding()]
    param()

    $candidate = Join-Path -Path $PSScriptRoot -ChildPath '..\..\config\enterpriseai.package.json'
    try {
        return (Resolve-Path -Path $candidate -ErrorAction Stop).Path
    }
    catch {
        return $candidate
    }
}

function Test-EAILoopbackUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$UriString
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate($UriString, [System.UriKind]::Absolute, [ref]$uri)) {
        return $false
    }

    if ($uri.Scheme -notin @('http', 'https')) {
        return $false
    }

    if ($uri.Host -eq 'localhost') {
        return $true
    }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($uri.Host, [ref]$address)) {
        return $false
    }

    $bytes = $address.GetAddressBytes()
    return ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $bytes[0] -eq 127)
}

function Test-EAIConfigValid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Config
    )

    foreach ($field in $script:EAIRequiredConfigFields) {
        if ($field -notin $Config.PSObject.Properties.Name) {
            Write-Verbose ('Missing config field {0}' -f $field)
            return $false
        }

        $value = $Config.$field
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            Write-Verbose ('Empty config field {0}' -f $field)
            return $false
        }
    }

    if (-not [System.IO.Path]::IsPathRooted([string]$Config.InstallRoot)) {
        Write-Verbose 'InstallRoot must be an absolute path.'
        return $false
    }

    if (-not [System.IO.Path]::IsPathRooted([string]$Config.ProgramDataRoot)) {
        Write-Verbose 'ProgramDataRoot must be an absolute path.'
        return $false
    }

    if (-not (Test-EAILoopbackUri -UriString ([string]$Config.OllamaEndpoint))) {
        Write-Verbose 'OllamaEndpoint must be loopback-only.'
        return $false
    }

    if (-not (Test-EAILoopbackUri -UriString ([string]$Config.LiteLLMEndpoint))) {
        Write-Verbose 'LiteLLMEndpoint must be loopback-only.'
        return $false
    }

    return $true
}

function Read-EAIPackageConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path = (Get-EAIConfigPath)
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('Configuration file not found: {0}' -f $Path)
    }

    $rawContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        throw ('Configuration file is empty: {0}' -f $Path)
    }

    try {
        $config = $rawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ('Failed to parse configuration file {0}. {1}' -f $Path, $_.Exception.Message)
    }

    if (-not (Test-EAIConfigValid -Config $config)) {
        throw ('Configuration file failed validation: {0}' -f $Path)
    }

    return $config
}

Export-ModuleMember -Function Get-EAIConfigPath, Read-EAIPackageConfig, Test-EAIConfigValid
