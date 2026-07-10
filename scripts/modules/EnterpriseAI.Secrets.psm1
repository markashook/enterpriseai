#Requires -Version 5.1
Set-StrictMode -Version Latest

function Import-EAIAclDependency {
    [CmdletBinding()]
    param()

    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'EnterpriseAI.Acl.psm1'
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
        Import-Module -Name $modulePath -Force -ErrorAction Stop | Out-Null
    }
}

function ConvertTo-EAISecretPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$SecureString
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

function Get-EAISecretFilePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI'
    )

    return Join-Path -Path $ProgramDataRoot -ChildPath 'Secrets\litellm.key'
}

function Set-EAILiteLLMApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$ApiKey,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    $secretPath = Get-EAISecretFilePath -ProgramDataRoot $ProgramDataRoot
    $secretDirectory = Split-Path -Path $secretPath -Parent
    if (-not (Test-Path -LiteralPath $secretDirectory -PathType Container)) {
        New-Item -Path $secretDirectory -ItemType Directory -Force | Out-Null
    }

    $plainText = ConvertTo-EAISecretPlainText -SecureString $ApiKey
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($secretPath, $plainText, $encoding)

    Import-EAIAclDependency
    if (Get-Command -Name Set-EAISecretsAcl -ErrorAction SilentlyContinue) {
        Set-EAISecretsAcl -SecretsPath $secretDirectory -ServiceAccountName $ServiceAccountName | Out-Null
    }

    return $secretPath
}

function Get-EAILiteLLMApiKey {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI'
    )

    $secretPath = Get-EAISecretFilePath -ProgramDataRoot $ProgramDataRoot
    if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
        throw ('LiteLLM API key file not found: {0}' -f $secretPath)
    }

    $plainText = (Get-Content -LiteralPath $secretPath -Raw -ErrorAction Stop).Trim()
    $secureString = New-Object System.Security.SecureString
    foreach ($character in $plainText.ToCharArray()) {
        $secureString.AppendChar($character)
    }

    $secureString.MakeReadOnly()
    return $secureString
}

function Test-EAISecretExists {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI'
    )

    return (Test-Path -LiteralPath (Get-EAISecretFilePath -ProgramDataRoot $ProgramDataRoot) -PathType Leaf)
}

function Test-EAISecretsAclRestricted {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    $secretDirectory = Split-Path -Path (Get-EAISecretFilePath -ProgramDataRoot $ProgramDataRoot) -Parent
    if (-not (Test-Path -LiteralPath $secretDirectory -PathType Container)) {
        return $false
    }

    $acl = Get-Acl -Path $secretDirectory
    $allowRules = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Allow' })
    $userRules = $allowRules | Where-Object { $_.IdentityReference.Value -eq 'BUILTIN\Users' }
    $serviceRules = $allowRules | Where-Object { $_.IdentityReference.Value -eq ('{0}\{1}' -f $env:COMPUTERNAME, $ServiceAccountName) }

    if ($userRules.Count -gt 0) {
        return $false
    }

    return ($serviceRules.Count -gt 0)
}

Export-ModuleMember -Function Set-EAILiteLLMApiKey, Get-EAILiteLLMApiKey, Test-EAISecretExists, Test-EAISecretsAclRestricted
