#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [Parameter()]
    [Security.SecureString]$ServiceAccountPassword,

    [Parameter()]
    [Security.SecureString]$LiteLLMApiKey
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ScriptName = [System.IO.Path]::GetFileName($PSCommandPath)
$script:LogPath = $null
$script:ExitCodes = [ordered]@{
    Success              = 0
    Failure              = 1
    InvalidArguments     = 2
    NotElevated          = 3
    UnsupportedOS        = 4
    DependencyFailed     = 5
    ServiceAccountFailed = 6
    AclFailed            = 7
    ServiceFailed        = 8
    FirewallFailed       = 9
    ValidationFailed     = 10
    LiteLLMAuthFailed    = 11
    EndpointBindingFailed= 12
    UninstallPartial     = 13
}

function Import-EAIModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Name
    )

    foreach ($moduleName in $Name) {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path 'modules' -ChildPath ($moduleName + '.psm1'))
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -Force -ErrorAction Stop
        }
        else {
            Write-Verbose ('Module not found at expected path: {0}' -f $modulePath)
        }
    }
}

function Initialize-EAILogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $logDirectory = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        New-Item -Path $LogPath -ItemType File -Force | Out-Null
    }

    $script:LogPath = $LogPath
}

function Write-EAIScriptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [hashtable]$Data
    )

    $writer = Get-Command -Name Write-EAILog -ErrorAction SilentlyContinue
    if ($writer) {
        $parameters = @{}
        if ($writer.Parameters.ContainsKey('Message')) { $parameters['Message'] = $Message }
        elseif ($writer.Parameters.ContainsKey('Text')) { $parameters['Text'] = $Message }

        if ($writer.Parameters.ContainsKey('Level')) { $parameters['Level'] = $Level }
        if ($writer.Parameters.ContainsKey('Component')) { $parameters['Component'] = $script:ScriptName }
        if ($writer.Parameters.ContainsKey('Path') -and $script:LogPath) { $parameters['Path'] = $script:LogPath }
        if ($writer.Parameters.ContainsKey('LogPath') -and $script:LogPath) { $parameters['LogPath'] = $script:LogPath }
        if ($writer.Parameters.ContainsKey('Data') -and $Data) { $parameters['Data'] = $Data }
        if ($writer.Parameters.ContainsKey('Metadata') -and $Data) { $parameters['Metadata'] = $Data }

        try {
            & $writer @parameters
            return
        }
        catch {
            Write-Verbose ('Write-EAILog failed, using local fallback. {0}' -f $_.Exception.Message)
        }
    }

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Level     = $Level
        Component = $script:ScriptName
        Message   = $Message
        Data      = $Data
    }

    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value ($entry | ConvertTo-Json -Depth 8 -Compress)
    }

    switch ($Level) {
        'ERROR' { Write-Verbose $Message }
        'WARN'  { Write-Verbose $Message }
        default { Write-Verbose $Message }
    }
}

function Exit-EAIScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if ($Message) {
        Write-EAIScriptLog -Message $Message -Level $Level
    }

    exit $Code
}

function Test-EAIIsAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-EAIElevation {
    [CmdletBinding()]
    param()

    if (-not (Test-EAIIsAdministrator)) {
        Exit-EAIScript -Code $script:ExitCodes.NotElevated -Message 'Script must be run with administrative privileges.' -Level 'ERROR'
    }
}

function Test-EAIWindowsSupported {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        return $false
    }

    $minimum = [version]'10.0.17763'
    $current = [Environment]::OSVersion.Version
    return ($current -ge $minimum)
}

function Get-EAIPackageRoot {
    [CmdletBinding()]
    param()

    return (Split-Path -Path $PSScriptRoot -Parent)
}

function Get-EAIPackageVersion {
    [CmdletBinding()]
    param()

    $versionPath = Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'VERSION'
    if (Test-Path -LiteralPath $versionPath) {
        return (Get-Content -Path $versionPath -ErrorAction Stop | Select-Object -First 1).Trim()
    }

    return '0.0.0'
}

function Get-EAIDefaultConfigPath {
    [CmdletBinding()]
    param()

    $programDataPath = 'C:\ProgramData\EnterpriseAI\Config\enterpriseai.package.json'
    if (Test-Path -LiteralPath $programDataPath) {
        return $programDataPath
    }

    return (Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'config\enterpriseai.package.json')
}

function Read-EAIConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter()]
        [switch]$SkipRuntimeChecks
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw 'Configuration file not found.'
    }

    $raw = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
    $configObject = $raw | ConvertFrom-Json -ErrorAction Stop

    $defaults = [ordered]@{
        PackageShortName                = 'EnterpriseAI'
        InstallRoot                     = 'C:\Program Files\EnterpriseAI'
        ProgramDataRoot                 = 'C:\ProgramData\EnterpriseAI'
        ServiceAccountName              = 'svc_EnterpriseAI'
        OllamaServiceName               = 'EnterpriseAI-Ollama'
        LiteLLMServiceName              = 'EnterpriseAI-LiteLLM'
        RegistryKey                     = 'HKLM:\Software\EnterpriseAI\LocalRuntimeGateway'
        FirewallRulePrefix              = 'EnterpriseAI-'
        RequireLiteLLMApiKey            = $true
        OllamaEndpoint                  = 'http://127.0.0.2:11434'
        LiteLLMEndpoint                 = 'http://127.0.0.1:4000'
        RuntimeModelPullsEnabled        = $false
        ApprovedModelRegistryUrl        = ''
        FailIfRegistryUrlMissingWhenPullsEnabled = $true
    }

    foreach ($key in $defaults.Keys) {
        if (-not ($configObject.PSObject.Properties.Name -contains $key) -or $null -eq $configObject.$key -or ($configObject.$key -is [string] -and [string]::IsNullOrWhiteSpace($configObject.$key))) {
            $configObject | Add-Member -MemberType NoteProperty -Name $key -Value $defaults[$key] -Force
        }
    }

    $requiredProperties = 'InstallRoot', 'ProgramDataRoot', 'ServiceAccountName', 'OllamaServiceName', 'LiteLLMServiceName', 'OllamaEndpoint', 'LiteLLMEndpoint'
    foreach ($requiredProperty in $requiredProperties) {
        if ([string]::IsNullOrWhiteSpace([string]$configObject.$requiredProperty)) {
            throw ('Configuration property is required: {0}' -f $requiredProperty)
        }
    }

    [void][Uri]$configObject.OllamaEndpoint
    [void][Uri]$configObject.LiteLLMEndpoint

    if (-not $SkipRuntimeChecks -and $configObject.RuntimeModelPullsEnabled -and $configObject.FailIfRegistryUrlMissingWhenPullsEnabled -and [string]::IsNullOrWhiteSpace([string]$configObject.ApprovedModelRegistryUrl)) {
        throw 'RuntimeModelPullsEnabled requires ApprovedModelRegistryUrl.'
    }

    return $configObject
}

function Ensure-EAIDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Test-EAIDirectoryHasPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $items = Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue | Where-Object {
        -not $_.PSIsContainer -and $_.Name -ne '.gitkeep'
    }

    return [bool]($items | Select-Object -First 1)
}

function Copy-EAIVendorPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-EAIDirectoryHasPayload -Path $Source)) {
        Write-EAIScriptLog -Message ('Skipping empty vendor directory: {0}' -f $Source) -Level 'INFO'
        return
    }

    Ensure-EAIDirectory -Path $Destination
    Copy-Item -Path (Join-Path -Path $Source -ChildPath '*') -Destination $Destination -Recurse -Force
}

function Test-EAIPackageIntegrity {
    [CmdletBinding()]
    param()

    $manifestPath = Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'manifest\hashes.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-EAIScriptLog -Message 'hashes.sha256 not found; skipping package integrity verification.' -Level 'WARN'
        return $true
    }

    $lines = Get-Content -Path $manifestPath -ErrorAction Stop | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#')
    }

    if (-not $lines) {
        Write-EAIScriptLog -Message 'hashes.sha256 is empty; skipping package integrity verification.' -Level 'WARN'
        return $true
    }

    $packageRoot = Get-EAIPackageRoot
    $validatedAny = $false
    foreach ($line in $lines) {
        if ($line -match 'PLACEHOLDER') {
            continue
        }

        $parts = $line -split '\s{2,}', 2
        if ($parts.Count -lt 2) {
            continue
        }

        $expectedHash = $parts[0].Trim().ToUpperInvariant()
        $relativeName = $parts[1].Trim()
        $matches = Get-ChildItem -Path $packageRoot -Recurse -File -Filter $relativeName -ErrorAction SilentlyContinue
        if (-not $matches) {
            Write-EAIScriptLog -Message ('Hash entry file not present in expanded package payload: {0}' -f $relativeName) -Level 'WARN'
            continue
        }

        foreach ($match in $matches) {
            $validatedAny = $true
            $actualHash = (Get-FileHash -Path $match.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actualHash -ne $expectedHash) {
                Write-EAIScriptLog -Message ('Hash mismatch for {0}' -f $match.FullName) -Level 'ERROR'
                return $false
            }
        }
    }

    if (-not $validatedAny) {
        Write-EAIScriptLog -Message 'No concrete hash entries were validated; continuing with warning.' -Level 'WARN'
    }
    else {
        Write-EAIScriptLog -Message 'Package integrity verification completed.' -Level 'INFO'
    }

    return $true
}

function Get-EAIPlainTextFromSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Invoke-EAIExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList,

        [Parameter()]
        [switch]$AllowFailure
    )

    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        $message = if ($output) { ($output | Out-String).Trim() } else { 'Command failed.' }
        throw ('{0} exited with code {1}: {2}' -f $FilePath, $exitCode, $message)
    }

    return ,$output
}

function Get-EAILocalAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ('{0}\{1}' -f $env:COMPUTERNAME, $Name)
}

function Test-EAILocalUserExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $getLocalUser = Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue
    if ($getLocalUser) {
        return [bool](Get-LocalUser -Name $Name -ErrorAction SilentlyContinue)
    }

    try {
        $null = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $Name)
        return $true
    }
    catch {
        return $false
    }
}

function Grant-EAILogOnAsServiceRight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,

        [Parameter(Mandatory = $true)]
        [string]$ProgramDataRoot
    )

    $statePath = Join-Path -Path $ProgramDataRoot -ChildPath 'State\SecEdit'
    Ensure-EAIDirectory -Path $statePath

    $exportPath = Join-Path -Path $statePath -ChildPath 'user-rights-export.inf'
    $importPath = Join-Path -Path $statePath -ChildPath 'user-rights-import.inf'
    $databasePath = Join-Path -Path $statePath -ChildPath 'user-rights.sdb'

    Invoke-EAIExternalCommand -FilePath 'secedit.exe' -ArgumentList @('/export', '/cfg', $exportPath, '/areas', 'USER_RIGHTS') | Out-Null

    $sid = ([System.Security.Principal.NTAccount]$AccountName).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $sidEntry = '*' + $sid
    $content = Get-Content -Path $exportPath -ErrorAction Stop
    $updated = $false
    $outputLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $content) {
        if ($line -match '^SeServiceLogonRight\s*=') {
            $existing = @()
            $parts = ($line -split '=', 2)[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($parts)) {
                $existing = $parts -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
            if ($existing -notcontains $sidEntry) {
                $existing += $sidEntry
            }
            $outputLines.Add('SeServiceLogonRight = ' + ($existing -join ','))
            $updated = $true
        }
        else {
            $outputLines.Add($line)
        }
    }

    if (-not $updated) {
        $outputLines.Add('SeServiceLogonRight = ' + $sidEntry)
    }

    Set-Content -Path $importPath -Value $outputLines -Encoding Unicode
    Invoke-EAIExternalCommand -FilePath 'secedit.exe' -ArgumentList @('/configure', '/db', $databasePath, '/cfg', $importPath, '/areas', 'USER_RIGHTS') | Out-Null
}

function Ensure-EAIServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [Security.SecureString]$Password,

        [Parameter(Mandatory = $true)]
        [string]$ProgramDataRoot,

        [Parameter()]
        [switch]$RepairOnly
    )

    $exists = Test-EAILocalUserExists -Name $Name
    $plainPassword = $null
    if ($Password) {
        $plainPassword = Get-EAIPlainTextFromSecureString -SecureString $Password
    }

    try {
        if (-not $exists) {
            if ($RepairOnly) {
                throw 'Service account is missing.'
            }
            if (-not $Password) {
                throw 'Service account password is required to create a new account.'
            }

            $newLocalUser = Get-Command -Name New-LocalUser -ErrorAction SilentlyContinue
            if ($newLocalUser) {
                New-LocalUser -Name $Name -Password $Password -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword -Description 'EnterpriseAI service account' | Out-Null
            }
            else {
                Invoke-EAIExternalCommand -FilePath 'net.exe' -ArgumentList @('user', $Name, $plainPassword, '/add', '/expires:never', '/passwordchg:no') | Out-Null
            }
        }
        elseif ($Password) {
            $setLocalUser = Get-Command -Name Set-LocalUser -ErrorAction SilentlyContinue
            if ($setLocalUser) {
                Set-LocalUser -Name $Name -Password $Password | Out-Null
            }
        }

        $enableLocalUser = Get-Command -Name Enable-LocalUser -ErrorAction SilentlyContinue
        if ($enableLocalUser) {
            Enable-LocalUser -Name $Name -ErrorAction SilentlyContinue
        }
        else {
            Invoke-EAIExternalCommand -FilePath 'net.exe' -ArgumentList @('user', $Name, '/active:yes') -AllowFailure | Out-Null
        }

        Grant-EAILogOnAsServiceRight -AccountName (Get-EAILocalAccountName -Name $Name) -ProgramDataRoot $ProgramDataRoot
    }
    finally {
        $plainPassword = $null
    }
}

function Disable-EAIServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-EAILocalUserExists -Name $Name)) {
        return
    }

    $disableLocalUser = Get-Command -Name Disable-LocalUser -ErrorAction SilentlyContinue
    if ($disableLocalUser) {
        Disable-LocalUser -Name $Name -ErrorAction SilentlyContinue
    }
    else {
        Invoke-EAIExternalCommand -FilePath 'net.exe' -ArgumentList @('user', $Name, '/active:no') -AllowFailure | Out-Null
    }
}

function Remove-EAIServiceAccountInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-EAILocalUserExists -Name $Name)) {
        return
    }

    $removeLocalUser = Get-Command -Name Remove-LocalUser -ErrorAction SilentlyContinue
    if ($removeLocalUser) {
        Remove-LocalUser -Name $Name -ErrorAction Stop
    }
    else {
        Invoke-EAIExternalCommand -FilePath 'net.exe' -ArgumentList @('user', $Name, '/delete') | Out-Null
    }
}

function Set-EAIAcls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $serviceAccount = Get-EAILocalAccountName -Name $Config.ServiceAccountName
    $grantSpecs = @(
        @{ Path = $Config.InstallRoot; Args = @('/inheritance:e', '/grant:r', 'Administrators:(OI)(CI)(F)', 'SYSTEM:(OI)(CI)(F)', ('{0}:(OI)(CI)(RX)' -f $serviceAccount)) },
        @{ Path = $Config.ProgramDataRoot; Args = @('/inheritance:e', '/grant:r', 'Administrators:(OI)(CI)(F)', 'SYSTEM:(OI)(CI)(F)', ('{0}:(OI)(CI)(RX)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Config'); Args = @('/grant:r', ('{0}:(OI)(CI)(R)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Secrets'); Args = @('/grant:r', ('{0}:(OI)(CI)(R)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Models'); Args = @('/grant:r', ('{0}:(OI)(CI)(RX)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Logs'); Args = @('/grant:r', ('{0}:(OI)(CI)(M)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'LiteLLM'); Args = @('/grant:r', ('{0}:(OI)(CI)(M)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Ollama'); Args = @('/grant:r', ('{0}:(OI)(CI)(M)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'State'); Args = @('/grant:r', ('{0}:(OI)(CI)(M)' -f $serviceAccount)) },
        @{ Path = (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Validation'); Args = @('/grant:r', ('{0}:(OI)(CI)(M)' -f $serviceAccount)) }
    )

    foreach ($grantSpec in $grantSpecs) {
        if (Test-Path -LiteralPath $grantSpec.Path) {
            Invoke-EAIExternalCommand -FilePath 'icacls.exe' -ArgumentList @($grantSpec.Path) + $grantSpec.Args | Out-Null
        }
    }
}

function Get-EAILiteLLMSecretPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Secrets\litellm-master-key.txt')
}

function Set-EAILiteLLMApiKeySecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter()]
        [Security.SecureString]$LiteLLMApiKey
    )

    $secretPath = Get-EAILiteLLMSecretPath -Config $Config
    Ensure-EAIDirectory -Path (Split-Path -Path $secretPath -Parent)

    if ($LiteLLMApiKey) {
        $plainText = Get-EAIPlainTextFromSecureString -SecureString $LiteLLMApiKey
        try {
            Set-Content -Path $secretPath -Value $plainText -Encoding ASCII -NoNewline -Force
            Write-EAIScriptLog -Message 'LiteLLM API key secret written to protected secrets path.' -Level 'INFO'
        }
        finally {
            $plainText = $null
        }
    }

    if ($Config.RequireLiteLLMApiKey -and -not (Test-Path -LiteralPath $secretPath)) {
        throw 'LiteLLM API key is required but was not provided and no existing secret is present.'
    }

    if (Test-Path -LiteralPath $secretPath) {
        Invoke-EAIExternalCommand -FilePath 'icacls.exe' -ArgumentList @($secretPath, '/inheritance:r', '/grant:r', 'Administrators:F', 'SYSTEM:F', ((Get-EAILocalAccountName -Name $Config.ServiceAccountName) + ':R')) | Out-Null
    }
}

function Get-EAIApprovedModels {
    [CmdletBinding()]
    param()

    $approvedPath = Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'config\approved-models.example.json'
    if (Test-Path -LiteralPath $approvedPath) {
        $approved = Get-Content -Path $approvedPath -Raw | ConvertFrom-Json
        if ($approved.Models) {
            return @($approved.Models | Where-Object { $_.Enabled -ne $false })
        }
    }

    return @(
        [pscustomobject]@{ Alias = 'approved-chat'; Backend = 'ollama_chat/approved-chat-model'; Description = 'Approved general chat model'; Enabled = $true },
        [pscustomobject]@{ Alias = 'approved-code'; Backend = 'ollama_chat/approved-code-model'; Description = 'Approved coding assistance model'; Enabled = $true }
    )
}

function Render-EAIOllamaEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $templatePath = Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'config\ollama.env.template'
    $outputPath = Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Config\ollama.env'
    Ensure-EAIDirectory -Path (Split-Path -Path $outputPath -Parent)

    $content = if (Test-Path -LiteralPath $templatePath) { Get-Content -Path $templatePath -Raw } else { '' }
    $content = [regex]::Replace($content, '(?m)^OLLAMA_HOST=.*$', ('OLLAMA_HOST={0}' -f $Config.OllamaEndpoint))
    $content = [regex]::Replace($content, '(?m)^OLLAMA_MODELS=.*$', ('OLLAMA_MODELS={0}' -f (Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Models')))
    if (-not $content) {
        $content = @"
OLLAMA_HOST=$($Config.OllamaEndpoint)
OLLAMA_MODELS=$($Config.ProgramDataRoot)\Models
OLLAMA_NOHISTORY=1
"@
    }

    Set-Content -Path $outputPath -Value $content -Encoding ASCII
    return $outputPath
}

function Render-EAILiteLLMConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $outputPath = Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Config\litellm.config.yaml'
    Ensure-EAIDirectory -Path (Split-Path -Path $outputPath -Parent)

    $liteUri = [Uri]$Config.LiteLLMEndpoint
    $ollamaUri = [Uri]$Config.OllamaEndpoint
    $models = Get-EAIApprovedModels
    $modelLines = foreach ($model in $models) {
@"
  - model_name: "$($model.Alias)"
    litellm_params:
      model: "$($model.Backend)"
      api_base: "$($Config.OllamaEndpoint)"
    model_info:
      require_auth: true
"@
    }

    $content = @"
# LiteLLM Configuration Template for EnterpriseAI
# Rendered during install/repair. Do not edit directly on workstations.

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  host: "$($liteUri.Host)"
  port: $($liteUri.Port)
  debug: false
  telemetry: false
  drop_params: false

litellm_settings:
  set_verbose: false

model_list:
$($modelLines -join [Environment]::NewLine)
router_settings:
  routing_strategy: "simple-shuffle"
  allowed_fails: 0
"@

    Set-Content -Path $outputPath -Value $content -Encoding UTF8
    return $outputPath
}

function Get-EAINssmPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $matches = Get-ChildItem -Path (Join-Path -Path $Config.InstallRoot -ChildPath 'service-wrapper') -Filter 'nssm.exe' -Recurse -File -ErrorAction SilentlyContinue
    if ($matches) {
        return ($matches | Select-Object -First 1).FullName
    }

    return $null
}

function Get-EAIOllamaExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $matches = Get-ChildItem -Path (Join-Path -Path $Config.InstallRoot -ChildPath 'ollama') -Filter 'ollama.exe' -Recurse -File -ErrorAction SilentlyContinue
    if ($matches) {
        return ($matches | Select-Object -First 1).FullName
    }

    throw 'Unable to locate ollama.exe in install root.'
}

function Get-EAIPythonExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $matches = Get-ChildItem -Path (Join-Path -Path $Config.InstallRoot -ChildPath 'python') -Filter 'python.exe' -Recurse -File -ErrorAction SilentlyContinue
    if ($matches) {
        return ($matches | Select-Object -First 1).FullName
    }

    throw 'Unable to locate python.exe in install root.'
}

function Test-EAIServiceExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Ensure-EAIWindowsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter()]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$StdOutLog,

        [Parameter(Mandatory = $true)]
        [string]$StdErrLog,

        [Parameter()]
        [hashtable]$Environment,

        [Parameter()]
        [Security.SecureString]$Password
    )

    Ensure-EAIDirectory -Path (Split-Path -Path $StdOutLog -Parent)
    Ensure-EAIDirectory -Path (Split-Path -Path $StdErrLog -Parent)

    $nssmPath = Get-EAINssmPath -Config $Config
    $accountName = '.\' + $Config.ServiceAccountName
    $plainPassword = if ($Password) { Get-EAIPlainTextFromSecureString -SecureString $Password } else { $null }
    $serviceExists = Test-EAIServiceExists -Name $Name

    try {
        if (-not $serviceExists -and -not $plainPassword) {
            throw 'Service account password is required to create a missing service.'
        }

        if ($nssmPath) {
            if (-not $serviceExists) {
                Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('install', $Name, $Executable, $Arguments) | Out-Null
            }

            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'AppDirectory', $WorkingDirectory) | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'Description', $Description) | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'Start', 'SERVICE_AUTO_START') | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'AppStdout', $StdOutLog) | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'AppStderr', $StdErrLog) | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'AppRotateFiles', '1') | Out-Null
            Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'AppRotateOnline', '1') | Out-Null
            if ($plainPassword) {
                Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('set', $Name, 'ObjectName', $accountName, $plainPassword) | Out-Null
            }
            if ($Environment -and $Environment.Count -gt 0) {
                $pairs = @()
                foreach ($key in $Environment.Keys) {
                    $pairs += ('{0}={1}' -f $key, $Environment[$key])
                }
                Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList (@('set', $Name, 'AppEnvironmentExtra') + $pairs) | Out-Null
            }
        }
        else {
            $binPath = '"{0}" {1}' -f $Executable, $Arguments
            if (-not (Test-EAIServiceExists -Name $Name)) {
                Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('create', $Name, 'binPath=', $binPath, 'start=', 'auto', 'obj=', $accountName, 'password=', $plainPassword) | Out-Null
            }
            else {
                Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('config', $Name, 'binPath=', $binPath, 'start=', 'auto', 'obj=', $accountName, 'password=', $plainPassword) | Out-Null
            }
            Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('description', $Name, $Description) | Out-Null
            Write-EAIScriptLog -Message ('NSSM was not found; environment customization for service {0} may be limited.' -f $Name) -Level 'WARN'
        }
    }
    finally {
        $plainPassword = $null
    }
}

function Set-EAIServiceRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('failure', $Name, 'reset=', '86400', 'actions=', 'restart/60000/restart/60000/restart/60000') | Out-Null
    Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('failureflag', $Name, '1') | Out-Null
}

function Start-EAIServiceSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        Start-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromMinutes(2))
    }
}

function Stop-EAIServiceSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $service.WaitForStatus('Stopped', [TimeSpan]::FromMinutes(2))
    }
}

function Remove-EAIWindowsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-EAIServiceExists -Name $Name)) {
        return
    }

    $nssmPath = Get-EAINssmPath -Config $Config
    if ($nssmPath) {
        Invoke-EAIExternalCommand -FilePath $nssmPath -ArgumentList @('remove', $Name, 'confirm') -AllowFailure | Out-Null
    }
    else {
        Invoke-EAIExternalCommand -FilePath 'sc.exe' -ArgumentList @('delete', $Name) -AllowFailure | Out-Null
    }
}

function Set-EAIFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $policyPath = Join-Path -Path (Get-EAIPackageRoot) -ChildPath 'config\firewall.policy.json'
    if (-not (Test-Path -LiteralPath $policyPath)) {
        throw 'Firewall policy file not found.'
    }

    $policy = Get-Content -Path $policyPath -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($rule in $policy.Rules) {
        $existing = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop | Out-Null
        }

        $parameters = @{
            Name        = $rule.Name
            DisplayName = $rule.Name
            Description = $rule.Description
            Direction   = $rule.Direction
            Action      = $rule.Action
            Enabled     = 'True'
            Profile     = 'Any'
            Protocol    = $rule.Protocol
        }
        if ($rule.PSObject.Properties.Name -contains 'LocalPort') { $parameters['LocalPort'] = [string]$rule.LocalPort }
        if ($rule.PSObject.Properties.Name -contains 'RemotePort') { $parameters['RemotePort'] = [string]$rule.RemotePort }
        if ($rule.PSObject.Properties.Name -contains 'RemoteAddress') { $parameters['RemoteAddress'] = [string]$rule.RemoteAddress }
        New-NetFirewallRule @parameters | Out-Null
    }
}

function Remove-EAIFirewallRulesByPrefix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ($Prefix + '*') } | Remove-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
}

function Write-EAIRegistryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $Config.RegistryKey)) {
        New-Item -Path $Config.RegistryKey -Force | Out-Null
    }

    $values = [ordered]@{
        PackageVersion      = Get-EAIPackageVersion
        InstallRoot         = $Config.InstallRoot
        ProgramDataRoot     = $Config.ProgramDataRoot
        ServiceAccountName  = $Config.ServiceAccountName
        OllamaServiceName   = $Config.OllamaServiceName
        LiteLLMServiceName  = $Config.LiteLLMServiceName
        ConfigPath          = $ConfigPath
        InstalledOnUtc      = (Get-Date).ToUniversalTime().ToString('o')
    }

    foreach ($key in $values.Keys) {
        New-ItemProperty -Path $Config.RegistryKey -Name $key -Value $values[$key] -PropertyType String -Force | Out-Null
    }
}

function Remove-EAIRegistryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-Path -LiteralPath $Config.RegistryKey) {
        Remove-Item -Path $Config.RegistryKey -Recurse -Force
    }
}

function Invoke-EAIHttpProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Headers,

        [Parameter()]
        [ValidateSet('Get', 'Post')]
        [string]$Method = 'Get'
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -Method $Method -Headers $Headers -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Content    = $response.Content
            Success    = $true
        }
    }
    catch {
        $statusCode = $null
        $content = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $content = $reader.ReadToEnd()
                $reader.Dispose()
            }
            catch {}
        }

        return [pscustomobject]@{
            StatusCode = $statusCode
            Content    = $content
            Success    = $false
            Error      = $_.Exception.Message
        }
    }
}

function Invoke-EAIValidationSuite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter()]
        [switch]$PersistReport
    )

    $results = New-Object System.Collections.Generic.List[object]
    $version = Get-EAIPackageVersion
    $secretPath = Get-EAILiteLLMSecretPath -Config $Config

    $results.Add([pscustomobject]@{ Name = 'InstallRoot'; Status = if (Test-Path -LiteralPath $Config.InstallRoot) { 'PASS' } else { 'FAIL' }; Details = $Config.InstallRoot })
    $results.Add([pscustomobject]@{ Name = 'ProgramDataRoot'; Status = if (Test-Path -LiteralPath $Config.ProgramDataRoot) { 'PASS' } else { 'FAIL' }; Details = $Config.ProgramDataRoot })
    $results.Add([pscustomobject]@{ Name = 'OllamaServiceExists'; Status = if (Test-EAIServiceExists -Name $Config.OllamaServiceName) { 'PASS' } else { 'FAIL' }; Details = $Config.OllamaServiceName })
    $results.Add([pscustomobject]@{ Name = 'LiteLLMServiceExists'; Status = if (Test-EAIServiceExists -Name $Config.LiteLLMServiceName) { 'PASS' } else { 'FAIL' }; Details = $Config.LiteLLMServiceName })

    if (Test-EAIServiceExists -Name $Config.OllamaServiceName) {
        $results.Add([pscustomobject]@{ Name = 'OllamaServiceRunning'; Status = if ((Get-Service -Name $Config.OllamaServiceName).Status -eq 'Running') { 'PASS' } else { 'FAIL' }; Details = ((Get-Service -Name $Config.OllamaServiceName).Status.ToString()) })
    }
    if (Test-EAIServiceExists -Name $Config.LiteLLMServiceName) {
        $results.Add([pscustomobject]@{ Name = 'LiteLLMServiceRunning'; Status = if ((Get-Service -Name $Config.LiteLLMServiceName).Status -eq 'Running') { 'PASS' } else { 'FAIL' }; Details = ((Get-Service -Name $Config.LiteLLMServiceName).Status.ToString()) })
    }

    $registryOk = $false
    if (Test-Path -LiteralPath $Config.RegistryKey) {
        try {
            $registryVersion = (Get-ItemProperty -Path $Config.RegistryKey -Name PackageVersion -ErrorAction Stop).PackageVersion
            $registryOk = ($registryVersion -eq $version)
        }
        catch {
            $registryOk = $false
        }
    }
    $results.Add([pscustomobject]@{ Name = 'RegistryState'; Status = if ($registryOk) { 'PASS' } else { 'FAIL' }; Details = $Config.RegistryKey })

    $unauthenticated = Invoke-EAIHttpProbe -Uri ($Config.LiteLLMEndpoint.TrimEnd('/') + '/v1/models')
    if ($Config.RequireLiteLLMApiKey) {
        $results.Add([pscustomobject]@{ Name = 'LiteLLMUnauthenticatedReject'; Status = if ($unauthenticated.StatusCode -eq 401) { 'PASS' } else { 'FAIL' }; Details = ('HTTP {0}' -f $unauthenticated.StatusCode) })
    }
    else {
        $results.Add([pscustomobject]@{ Name = 'LiteLLMUnauthenticatedReject'; Status = 'SKIP'; Details = 'API key requirement disabled in configuration.' })
    }

    if (Test-Path -LiteralPath $secretPath) {
        $apiKey = (Get-Content -Path $secretPath -Raw).Trim()
        $authenticated = Invoke-EAIHttpProbe -Uri ($Config.LiteLLMEndpoint.TrimEnd('/') + '/v1/models') -Headers @{ Authorization = 'Bearer ' + $apiKey }
        $authStatus = if ($authenticated.StatusCode -in @(200, 201)) { 'PASS' } else { 'FAIL' }
        $results.Add([pscustomobject]@{ Name = 'LiteLLMAuthenticatedAccess'; Status = $authStatus; Details = ('HTTP {0}' -f $authenticated.StatusCode) })
    }
    elseif ($Config.RequireLiteLLMApiKey) {
        $results.Add([pscustomobject]@{ Name = 'LiteLLMAuthenticatedAccess'; Status = 'FAIL'; Details = 'LiteLLM API key secret is missing.' })
    }
    else {
        $results.Add([pscustomobject]@{ Name = 'LiteLLMAuthenticatedAccess'; Status = 'SKIP'; Details = 'No API key configured.' })
    }

    $ollama = Invoke-EAIHttpProbe -Uri ($Config.OllamaEndpoint.TrimEnd('/') + '/api/tags')
    $results.Add([pscustomobject]@{ Name = 'OllamaEndpointReachable'; Status = if ($ollama.StatusCode -in @(200, 404)) { 'PASS' } else { 'FAIL' }; Details = ('HTTP {0}' -f $ollama.StatusCode) })

    if ($Config.RuntimeModelPullsEnabled -and [string]::IsNullOrWhiteSpace([string]$Config.ApprovedModelRegistryUrl)) {
        $results.Add([pscustomobject]@{ Name = 'RuntimePullPolicy'; Status = 'FAIL'; Details = 'ApprovedModelRegistryUrl is required when RuntimeModelPullsEnabled is true.' })
    }
    else {
        $results.Add([pscustomobject]@{ Name = 'RuntimePullPolicy'; Status = 'PASS'; Details = 'Runtime model pull policy is valid.' })
    }

    if ($PersistReport) {
        $reportPath = Join-Path -Path $Config.ProgramDataRoot -ChildPath 'Validation\latest-validation.json'
        Ensure-EAIDirectory -Path (Split-Path -Path $reportPath -Parent)
        $results | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8
    }

    return $results
}

function Get-EAIValidationExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results
    )

    if ($Results | Where-Object { $_.Status -eq 'FAIL' }) {
        return $script:ExitCodes.ValidationFailed
    }

    return $script:ExitCodes.Success
}

Import-EAIModules -Name @(
    'EnterpriseAI.Logging',
    'EnterpriseAI.Config',
    'EnterpriseAI.Accounts',
    'EnterpriseAI.Acl',
    'EnterpriseAI.Services',
    'EnterpriseAI.Secrets',
    'EnterpriseAI.Firewall',
    'EnterpriseAI.Validation'
)

try {
    if (-not (Test-EAIIsAdministrator)) {
        Exit-EAIScript -Code $script:ExitCodes.NotElevated -Message 'Install requires elevation.' -Level 'ERROR'
    }

    if (-not (Test-EAIWindowsSupported)) {
        Exit-EAIScript -Code $script:ExitCodes.UnsupportedOS -Message 'Unsupported operating system. Windows 10 / Server 2019 or newer is required.' -Level 'ERROR'
    }

    try {
        $config = Read-EAIConfigFile -ConfigPath $ConfigPath
    }
    catch {
        Write-Error ('Configuration validation failed: {0}' -f $_.Exception.Message)
        exit $script:ExitCodes.InvalidArguments
    }

    Initialize-EAILogging -LogPath (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Install\install.log')
    Write-EAIScriptLog -Message 'Starting EnterpriseAI installation.' -Level 'INFO'

    if (-not (Test-EAIPackageIntegrity)) {
        Exit-EAIScript -Code $script:ExitCodes.DependencyFailed -Message 'Package integrity verification failed.' -Level 'ERROR'
    }

    $installDirectories = @(
        $config.InstallRoot,
        (Join-Path -Path $config.InstallRoot -ChildPath 'bin'),
        (Join-Path -Path $config.InstallRoot -ChildPath 'ollama'),
        (Join-Path -Path $config.InstallRoot -ChildPath 'litellm'),
        (Join-Path -Path $config.InstallRoot -ChildPath 'python'),
        (Join-Path -Path $config.InstallRoot -ChildPath 'service-wrapper')
    )
    $programDataDirectories = @(
        $config.ProgramDataRoot,
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Config'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'LiteLLM'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Ollama'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Models'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Secrets'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'State'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Validation'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Install'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Repair'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Uninstall'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\LiteLLM'),
        (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Ollama')
    )

    foreach ($directory in ($installDirectories + $programDataDirectories)) {
        if ($PSCmdlet.ShouldProcess($directory, 'Ensure directory exists')) {
            Ensure-EAIDirectory -Path $directory
        }
    }

    $packageRoot = Get-EAIPackageRoot
    $vendorMappings = @(
        @{ Source = (Join-Path -Path $packageRoot -ChildPath 'vendor\ollama'); Destination = (Join-Path -Path $config.InstallRoot -ChildPath 'ollama') },
        @{ Source = (Join-Path -Path $packageRoot -ChildPath 'vendor\litellm'); Destination = (Join-Path -Path $config.InstallRoot -ChildPath 'litellm') },
        @{ Source = (Join-Path -Path $packageRoot -ChildPath 'vendor\python'); Destination = (Join-Path -Path $config.InstallRoot -ChildPath 'python') },
        @{ Source = (Join-Path -Path $packageRoot -ChildPath 'vendor\service-wrapper'); Destination = (Join-Path -Path $config.InstallRoot -ChildPath 'service-wrapper') }
    )

    foreach ($mapping in $vendorMappings) {
        if ($PSCmdlet.ShouldProcess($mapping.Destination, 'Stage vendor runtime payload')) {
            Copy-EAIVendorPayload -Source $mapping.Source -Destination $mapping.Destination
        }
    }

    $versionPath = Join-Path -Path $config.InstallRoot -ChildPath 'VERSION'
    if ($PSCmdlet.ShouldProcess($versionPath, 'Write package version file')) {
        Set-Content -Path $versionPath -Value (Get-EAIPackageVersion) -Encoding ASCII -Force
    }

    try {
        if ($PSCmdlet.ShouldProcess($config.ServiceAccountName, 'Create or repair service account')) {
            Ensure-EAIServiceAccount -Name $config.ServiceAccountName -Password $ServiceAccountPassword -ProgramDataRoot $config.ProgramDataRoot
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.ServiceAccountFailed -Message ('Service account operation failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    try {
        if ($PSCmdlet.ShouldProcess($config.ProgramDataRoot, 'Apply filesystem ACLs')) {
            Set-EAIAcls -Config $config
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.AclFailed -Message ('ACL application failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    try {
        if ($PSCmdlet.ShouldProcess((Join-Path -Path $config.ProgramDataRoot -ChildPath 'Secrets'), 'Write LiteLLM API key secret')) {
            Set-EAILiteLLMApiKeySecret -Config $config -LiteLLMApiKey $LiteLLMApiKey
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.Failure -Message ('LiteLLM secret operation failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    $ollamaEnvPath = $null
    $litellmConfigPath = $null
    if ($PSCmdlet.ShouldProcess((Join-Path -Path $config.ProgramDataRoot -ChildPath 'Config'), 'Render runtime configuration files')) {
        $ollamaEnvPath = Render-EAIOllamaEnvironment -Config $config
        $litellmConfigPath = Render-EAILiteLLMConfiguration -Config $config
    }

    try {
        $ollamaExe = Get-EAIOllamaExecutablePath -Config $config
        $pythonExe = Get-EAIPythonExecutablePath -Config $config
        $secretPath = Get-EAILiteLLMSecretPath -Config $config
        $liteEnv = @{
            LITELLM_MASTER_KEY = if (Test-Path -LiteralPath $secretPath) { (Get-Content -Path $secretPath -Raw).Trim() } else { '' }
            OLLAMA_ENDPOINT    = $config.OllamaEndpoint
            PYTHONPATH         = (Join-Path -Path $config.InstallRoot -ChildPath 'litellm')
        }
        $ollamaEnv = @{}
        if ($ollamaEnvPath -and (Test-Path -LiteralPath $ollamaEnvPath)) {
            foreach ($line in (Get-Content -Path $ollamaEnvPath)) {
                if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.Trim().StartsWith('#') -and $line.Contains('=')) {
                    $key, $value = $line.Split('=', 2)
                    $ollamaEnv[$key] = $value
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($config.OllamaServiceName, 'Create or update Ollama service')) {
            Ensure-EAIWindowsService -Config $config -Name $config.OllamaServiceName -Executable $ollamaExe -Arguments 'serve' -WorkingDirectory (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Ollama') -Description 'EnterpriseAI local Ollama runtime.' -StdOutLog (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Ollama\stdout.log') -StdErrLog (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\Ollama\stderr.log') -Environment $ollamaEnv -Password $ServiceAccountPassword
        }

        $liteUri = [Uri]$config.LiteLLMEndpoint
        $liteArguments = ('-m litellm --config "{0}" --host {1} --port {2}' -f $litellmConfigPath, $liteUri.Host, $liteUri.Port)
        if ($PSCmdlet.ShouldProcess($config.LiteLLMServiceName, 'Create or update LiteLLM service')) {
            Ensure-EAIWindowsService -Config $config -Name $config.LiteLLMServiceName -Executable $pythonExe -Arguments $liteArguments -WorkingDirectory (Join-Path -Path $config.ProgramDataRoot -ChildPath 'LiteLLM') -Description 'EnterpriseAI LiteLLM gateway service.' -StdOutLog (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\LiteLLM\stdout.log') -StdErrLog (Join-Path -Path $config.ProgramDataRoot -ChildPath 'Logs\LiteLLM\stderr.log') -Environment $liteEnv -Password $ServiceAccountPassword
        }

        if ($PSCmdlet.ShouldProcess($config.OllamaServiceName, 'Configure service recovery')) {
            Set-EAIServiceRecovery -Name $config.OllamaServiceName
        }
        if ($PSCmdlet.ShouldProcess($config.LiteLLMServiceName, 'Configure service recovery')) {
            Set-EAIServiceRecovery -Name $config.LiteLLMServiceName
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.ServiceFailed -Message ('Service configuration failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    try {
        if ($PSCmdlet.ShouldProcess($config.FirewallRulePrefix, 'Create firewall rules')) {
            Set-EAIFirewallRules -Config $config
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.FirewallFailed -Message ('Firewall configuration failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    try {
        if ($PSCmdlet.ShouldProcess($config.OllamaServiceName, 'Start Ollama service')) {
            Start-EAIServiceSafe -Name $config.OllamaServiceName
        }
        if ($PSCmdlet.ShouldProcess($config.LiteLLMServiceName, 'Start LiteLLM service')) {
            Start-EAIServiceSafe -Name $config.LiteLLMServiceName
        }
    }
    catch {
        Exit-EAIScript -Code $script:ExitCodes.ServiceFailed -Message ('Service start failed: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }

    $validationResults = Invoke-EAIValidationSuite -Config $config -PersistReport
    if ($validationResults | Where-Object { $_.Status -eq 'FAIL' }) {
        Write-EAIScriptLog -Message 'Post-install validation reported failures.' -Level 'ERROR'
        $validationResults | ConvertTo-Json -Depth 6 | Write-Verbose
        Exit-EAIScript -Code $script:ExitCodes.ValidationFailed -Message 'Installation validation failed.' -Level 'ERROR'
    }

    if ($PSCmdlet.ShouldProcess($config.RegistryKey, 'Write registry package state')) {
        Write-EAIRegistryState -Config $config -ConfigPath $ConfigPath
    }

    Write-EAIScriptLog -Message 'EnterpriseAI installation completed successfully.' -Level 'INFO'
    exit $script:ExitCodes.Success
}
catch {
    if ($script:LogPath) {
        Write-EAIScriptLog -Message ('Unhandled install error: {0}' -f $_.Exception.Message) -Level 'ERROR'
    }
    else {
        Write-Error $_.Exception.Message
    }
    exit $script:ExitCodes.Failure
}
