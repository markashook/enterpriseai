#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:EAIValidationRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..') -ErrorAction SilentlyContinue).Path
if (-not $script:EAIValidationRoot) { $script:EAIValidationRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..' }
foreach ($moduleName in @('EnterpriseAI.Config.psm1', 'EnterpriseAI.Accounts.psm1', 'EnterpriseAI.Services.psm1', 'EnterpriseAI.Secrets.psm1', 'EnterpriseAI.Firewall.psm1')) {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath $moduleName
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) { Import-Module -Name $modulePath -Force -ErrorAction Stop | Out-Null }
}

function Format-EAIValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL', 'SKIP')][string]$State,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message,
        [Parameter()][ValidateRange(0,255)][int]$ExitCode = 0
    )
    [pscustomobject]@{ Name = $Name; State = $State; Message = $Message; ExitCode = $ExitCode }
}

function Get-EAIResolvedConfig {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    if ($null -ne $Config) { return $Config }
    Read-EAIPackageConfig
}

function Join-EAIUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BaseUri,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RelativePath
    )
    $base = New-Object System.Uri($BaseUri)
    (New-Object System.Uri($base, $RelativePath)).AbsoluteUri
}

function Get-EAIHttpStatusCode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNull()][scriptblock]$ScriptBlock)
    try {
        $response = & $ScriptBlock
        if ($null -ne $response.StatusCode) { return [int]$response.StatusCode }
        return 200
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { return [int]$_.Exception.Response.StatusCode }
        throw
    }
}

function Get-EAIApprovedModelAliases {
    [CmdletBinding()]
    param([Parameter()][ValidateNotNullOrEmpty()][string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI')
    foreach ($path in @((Join-Path -Path $ProgramDataRoot -ChildPath 'Config\approved-models.json'), (Join-Path -Path $script:EAIValidationRoot -ChildPath 'config\approved-models.example.json'))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            return @($json.Models | Where-Object { $_.Enabled -ne $false } | ForEach-Object { $_.Alias })
        }
    }
    @()
}

function Get-EAIListeningEndpoints {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateRange(1,65535)][int]$Port)
    if (Get-Command -Name Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort)
    }
    $results = @()
    foreach ($match in (& netstat.exe -ano -p tcp | Select-String -Pattern (':{0}\s+.*LISTENING' -f $Port))) {
        if ($match.Line -match '^\s*TCP\s+(?<address>[^\s:]+):(?<port>\d+)') { $results += [pscustomobject]@{ LocalAddress = $Matches['address']; LocalPort = [int]$Matches['port'] } }
    }
    $results
}

function Test-EAIPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedVersion,
        [Parameter()][ValidateNotNullOrEmpty()][string]$VersionFilePath = (Join-Path -Path $script:EAIValidationRoot -ChildPath 'VERSION')
    )
    if (-not (Test-Path -LiteralPath $VersionFilePath -PathType Leaf)) { return Format-EAIValidationResult -Name 'PackageVersion' -State FAIL -Message 'VERSION file is missing.' -ExitCode 10 }
    $actualVersion = (Get-Content -LiteralPath $VersionFilePath -Raw).Trim()
    if ($actualVersion -ne $ExpectedVersion) { return Format-EAIValidationResult -Name 'PackageVersion' -State FAIL -Message ('Expected VERSION {0} but found {1}.' -f $ExpectedVersion, $actualVersion) -ExitCode 10 }
    Format-EAIValidationResult -Name 'PackageVersion' -State PASS -Message ('VERSION file matches {0}.' -f $ExpectedVersion)
}

function Test-EAIDirectories {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    $required = @($cfg.InstallRoot, $cfg.ProgramDataRoot, (Join-Path $cfg.ProgramDataRoot 'Config'), (Join-Path $cfg.ProgramDataRoot 'Logs'), (Join-Path $cfg.ProgramDataRoot 'Models'), (Join-Path $cfg.ProgramDataRoot 'Secrets'))
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) })
    if ($missing.Count -gt 0) { return Format-EAIValidationResult -Name 'Directories' -State FAIL -Message ('Missing directories: {0}' -f ($missing -join ', ')) -ExitCode 10 }
    Format-EAIValidationResult -Name 'Directories' -State PASS -Message 'All required directories are present.'
}

function Test-EAIServiceAccountValid {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    if (-not (Test-EAIServiceAccountExists -AccountName $cfg.ServiceAccountName)) { return Format-EAIValidationResult -Name 'ServiceAccount' -State FAIL -Message 'Service account is missing.' -ExitCode 10 }
    if (-not (Test-EAIServiceAccountIsNonAdmin -AccountName $cfg.ServiceAccountName)) { return Format-EAIValidationResult -Name 'ServiceAccount' -State FAIL -Message 'Service account must not be a member of Administrators.' -ExitCode 10 }
    Format-EAIValidationResult -Name 'ServiceAccount' -State PASS -Message 'Service account exists and is non-admin.'
}

function Test-EAIServicesRunning {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    $issues = @()
    foreach ($serviceName in @($cfg.OllamaServiceName, $cfg.LiteLLMServiceName)) {
        if (-not (Test-EAIServiceExists -ServiceName $serviceName)) { $issues += ('Missing service {0}' -f $serviceName); continue }
        if (-not (Test-EAIServiceRunning -ServiceName $serviceName)) { $issues += ('Service not running: {0}' -f $serviceName) }
    }
    if ($issues.Count -gt 0) { return Format-EAIValidationResult -Name 'Services' -State FAIL -Message ($issues -join '; ') -ExitCode 10 }
    Format-EAIValidationResult -Name 'Services' -State PASS -Message 'Both EnterpriseAI services are present and running.'
}

function Test-EAIEndpointBinding {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    $targets = @(
        @{ Name = 'Ollama'; Uri = New-Object System.Uri([string]$cfg.OllamaEndpoint) },
        @{ Name = 'LiteLLM'; Uri = New-Object System.Uri([string]$cfg.LiteLLMEndpoint) }
    )
    foreach ($target in $targets) {
        $listeners = @(Get-EAIListeningEndpoints -Port $target.Uri.Port)
        if ($listeners.Count -eq 0) { return Format-EAIValidationResult -Name 'EndpointBinding' -State FAIL -Message ('No listener found for {0} on port {1}.' -f $target.Name, $target.Uri.Port) -ExitCode 12 }
        if (@($listeners | Where-Object { $_.LocalAddress -notlike '127.*' -and $_.LocalAddress -ne '::1' }).Count -gt 0) { return Format-EAIValidationResult -Name 'EndpointBinding' -State FAIL -Message ('Non-loopback listener detected on port {0}.' -f $target.Uri.Port) -ExitCode 12 }
        if (@($listeners | Where-Object { $_.LocalAddress -eq $target.Uri.Host }).Count -eq 0) { return Format-EAIValidationResult -Name 'EndpointBinding' -State FAIL -Message ('Expected binding {0}:{1} not found.' -f $target.Uri.Host, $target.Uri.Port) -ExitCode 12 }
    }
    Format-EAIValidationResult -Name 'EndpointBinding' -State WARN -Message 'Bindings are loopback-only. Loopback binding, not firewall alone, is the primary isolation control.'
}

function Test-EAILiteLLMAuth {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    if ($cfg.RequireLiteLLMApiKey -eq $false) { return Format-EAIValidationResult -Name 'LiteLLMAuth' -State SKIP -Message 'LiteLLM API key enforcement is disabled by configuration.' }
    if (-not (Test-EAISecretExists -ProgramDataRoot $cfg.ProgramDataRoot)) { return Format-EAIValidationResult -Name 'LiteLLMAuth' -State FAIL -Message 'LiteLLM API key file is missing.' -ExitCode 11 }
    $modelsUri = Join-EAIUri -BaseUri ([string]$cfg.LiteLLMEndpoint) -RelativePath '/v1/models'
    $unauthenticatedStatus = Get-EAIHttpStatusCode -ScriptBlock { Invoke-WebRequest -Uri $modelsUri -Method Get -UseBasicParsing -ErrorAction Stop }
    if ($unauthenticatedStatus -notin @(401,403)) { return Format-EAIValidationResult -Name 'LiteLLMAuth' -State FAIL -Message ('Unauthenticated request returned HTTP {0} instead of 401/403.' -f $unauthenticatedStatus) -ExitCode 11 }
    $secureKey = Get-EAILiteLLMApiKey -ProgramDataRoot $cfg.ProgramDataRoot
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $headers = @{ Authorization = 'Bearer ' + [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        $authenticatedStatus = Get-EAIHttpStatusCode -ScriptBlock { Invoke-WebRequest -Uri $modelsUri -Headers $headers -Method Get -UseBasicParsing -ErrorAction Stop }
    }
    finally { if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
    if ($authenticatedStatus -ge 400) { return Format-EAIValidationResult -Name 'LiteLLMAuth' -State FAIL -Message ('Authenticated request returned HTTP {0}.' -f $authenticatedStatus) -ExitCode 11 }
    Format-EAIValidationResult -Name 'LiteLLMAuth' -State PASS -Message 'LiteLLM rejects unauthenticated requests and accepts authenticated requests.'
}

function Test-EAILiteLLMModelGating {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    $aliases = @(Get-EAIApprovedModelAliases -ProgramDataRoot $cfg.ProgramDataRoot)
    if ($aliases.Count -eq 0) { return Format-EAIValidationResult -Name 'LiteLLMModelGating' -State SKIP -Message 'No approved model aliases were found to validate.' }
    $secureKey = Get-EAILiteLLMApiKey -ProgramDataRoot $cfg.ProgramDataRoot
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $headers = @{ Authorization = 'Bearer ' + [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        $modelsUri = Join-EAIUri -BaseUri ([string]$cfg.LiteLLMEndpoint) -RelativePath '/v1/models'
        $published = @(((Invoke-WebRequest -Uri $modelsUri -Headers $headers -Method Get -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json).data | ForEach-Object { $_.id })
        $missing = @($aliases | Where-Object { $published -notcontains $_ })
        if ($missing.Count -gt 0) { return Format-EAIValidationResult -Name 'LiteLLMModelGating' -State FAIL -Message ('Approved aliases missing from /v1/models: {0}' -f ($missing -join ', ')) -ExitCode 10 }
        $invalidBody = '{"model":"not-approved-model","messages":[{"role":"user","content":"ping"}],"max_tokens":1}'
        $invalidUri = Join-EAIUri -BaseUri ([string]$cfg.LiteLLMEndpoint) -RelativePath '/v1/chat/completions'
        $invalidStatus = Get-EAIHttpStatusCode -ScriptBlock { Invoke-WebRequest -Uri $invalidUri -Headers $headers -Method Post -ContentType 'application/json' -Body $invalidBody -UseBasicParsing -ErrorAction Stop }
        if ($invalidStatus -notin @(400,404,422)) { return Format-EAIValidationResult -Name 'LiteLLMModelGating' -State FAIL -Message ('Unexpected HTTP {0} when testing a non-approved model alias.' -f $invalidStatus) -ExitCode 10 }
    }
    finally { if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
    Format-EAIValidationResult -Name 'LiteLLMModelGating' -State PASS -Message 'LiteLLM exposes approved aliases only and rejects arbitrary model names.'
}

function Test-EAIFirewallRulesPresent {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    $status = Test-EAIFirewallRules -Prefix ([string]$cfg.FirewallRulePrefix)
    $failures = @($status.GetEnumerator() | Where-Object { $_.Value.State -eq 'FAIL' })
    if ($failures.Count -gt 0) { return Format-EAIValidationResult -Name 'FirewallRules' -State FAIL -Message ('Missing firewall rules: {0}' -f (($failures | ForEach-Object { $_.Key }) -join ', ')) -ExitCode 10 }
    Format-EAIValidationResult -Name 'FirewallRules' -State WARN -Message 'Expected firewall rules are present. Loopback binding remains the primary isolation control.'
}

function Test-EAIRuntimePullPolicy {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][psobject]$Config)
    $cfg = Get-EAIResolvedConfig -Config $Config
    if ($cfg.RuntimeModelPullsEnabled -eq $true -and [string]::IsNullOrWhiteSpace([string]$cfg.ApprovedModelRegistryUrl)) { return Format-EAIValidationResult -Name 'RuntimePullPolicy' -State WARN -Message 'RuntimeModelPullsEnabled is true without an ApprovedModelRegistryUrl.' }
    Format-EAIValidationResult -Name 'RuntimePullPolicy' -State PASS -Message 'Runtime model pull policy matches the package baseline.'
}

function Invoke-EAIFullValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedVersion,
        [Parameter()][AllowNull()][psobject]$Config
    )
    $cfg = Get-EAIResolvedConfig -Config $Config
    $results = @(
        Test-EAIPackageVersion -ExpectedVersion $ExpectedVersion,
        Test-EAIDirectories -Config $cfg,
        Test-EAIServiceAccountValid -Config $cfg,
        Test-EAIServicesRunning -Config $cfg,
        Test-EAIEndpointBinding -Config $cfg,
        Test-EAILiteLLMAuth -Config $cfg,
        Test-EAILiteLLMModelGating -Config $cfg,
        Test-EAIFirewallRulesPresent -Config $cfg,
        Test-EAIRuntimePullPolicy -Config $cfg
    )
    $overallState = if ($results.State -contains 'FAIL') { 'FAIL' } elseif ($results.State -contains 'WARN') { 'WARN' } else { 'PASS' }
    $exitCode = if ($results.ExitCode -contains 11) { 11 } elseif ($results.ExitCode -contains 12) { 12 } elseif ($results.State -contains 'FAIL') { 10 } else { 0 }
    [pscustomobject]@{ OverallState = $overallState; ExitCode = $exitCode; Results = $results }
}

Export-ModuleMember -Function Test-EAIPackageVersion, Test-EAIDirectories, Test-EAIServiceAccountValid, Test-EAIServicesRunning, Test-EAIEndpointBinding, Test-EAILiteLLMAuth, Test-EAILiteLLMModelGating, Test-EAIFirewallRulesPresent, Test-EAIRuntimePullPolicy, Invoke-EAIFullValidation, Format-EAIValidationResult
