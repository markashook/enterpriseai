#Requires -Version 5.1
Set-StrictMode -Version Latest

function ConvertTo-EAIServicePlainText {
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

function Get-EAIServiceCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password
    )

    return New-Object System.Management.Automation.PSCredential(('.\{0}' -f $ServiceAccountName), $Password)
}

function Get-EAIServiceDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    return Get-CimInstance -ClassName Win32_Service -Filter ('Name = "{0}"' -f $ServiceName) -ErrorAction SilentlyContinue
}

function Test-EAIServiceExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    return ($null -ne (Get-EAIServiceDefinition -ServiceName $ServiceName))
}

function Test-EAIServiceRunning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    return ($null -ne $service -and $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)
}

function New-EAIOllamaService {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName = 'EnterpriseAI-Ollama',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath = 'C:\Program Files\EnterpriseAI\Runtime\ollama.exe',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI',

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password
    )

    if (Test-EAIServiceExists -ServiceName $ServiceName) {
        Remove-EAIService -ServiceName $ServiceName | Out-Null
    }

    # TODO: Verify the exact Ollama Windows service command line for the packaged runtime version.
    $binaryPath = ('"{0}" serve' -f $ExecutablePath)
    $credential = Get-EAIServiceCredential -ServiceAccountName $ServiceAccountName -Password $Password
    New-Service -Name $ServiceName -BinaryPathName $binaryPath -Credential $credential -DisplayName $ServiceName -Description 'EnterpriseAI local Ollama backend bound to 127.0.0.2:11434' -StartupType Automatic
    Set-EAIServiceRecovery -ServiceName $ServiceName | Out-Null
    return Get-EAIServiceDefinition -ServiceName $ServiceName
}

function New-EAILiteLLMService {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName = 'EnterpriseAI-LiteLLM',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$PythonPath = 'C:\Program Files\EnterpriseAI\Python\python.exe',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI',

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password
    )

    if (Test-EAIServiceExists -ServiceName $ServiceName) {
        Remove-EAIService -ServiceName $ServiceName | Out-Null
    }

    $configPath = Join-Path -Path $ProgramDataRoot -ChildPath 'Config\litellm.config.yaml'
    # TODO: Verify the exact LiteLLM proxy startup command for the packaged Windows runtime.
    $binaryPath = ('"{0}" -m litellm.proxy --config "{1}" --host 127.0.0.1 --port 4000' -f $PythonPath, $configPath)
    $credential = Get-EAIServiceCredential -ServiceAccountName $ServiceAccountName -Password $Password
    New-Service -Name $ServiceName -BinaryPathName $binaryPath -Credential $credential -DisplayName $ServiceName -Description 'EnterpriseAI LiteLLM gateway bound to 127.0.0.1:4000' -StartupType Automatic
    Set-EAIServiceRecovery -ServiceName $ServiceName | Out-Null
    return Get-EAIServiceDefinition -ServiceName $ServiceName
}

function Set-EAIServiceRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    & sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ('Failed to configure service recovery for {0}.' -f $ServiceName)
    }

    & sc.exe failureflag $ServiceName 1 | Out-Null
    return $true
}

function Start-EAIService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName,

        [Parameter()]
        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 60
    )

    Start-Service -Name $ServiceName -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            return $true
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw ('Timed out starting service {0}.' -f $ServiceName)
}

function Stop-EAIService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName,

        [Parameter()]
        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 60
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return $false
    }

    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -ErrorAction Stop
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $service.Refresh()
        if ($service.Status -eq 'Stopped') {
            return $true
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw ('Timed out stopping service {0}.' -f $ServiceName)
}

function Remove-EAIService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    if (-not (Test-EAIServiceExists -ServiceName $ServiceName)) {
        return $false
    }

    Stop-EAIService -ServiceName $ServiceName -TimeoutSeconds 60 | Out-Null
    & sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ('Failed to delete service {0}.' -f $ServiceName)
    }

    return $true
}

function Repair-EAIServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$InstallRoot = 'C:\Program Files\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OllamaServiceName = 'EnterpriseAI-Ollama',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LiteLLMServiceName = 'EnterpriseAI-LiteLLM'
    )

    $ollamaPath = Join-Path -Path $InstallRoot -ChildPath 'Runtime\ollama.exe'
    $pythonPath = Join-Path -Path $InstallRoot -ChildPath 'Python\python.exe'

    $ollamaExpectedPath = ('"{0}" serve' -f $ollamaPath)
    $liteExpectedPath = ('"{0}" -m litellm.proxy --config "{1}" --host 127.0.0.1 --port 4000' -f $pythonPath, (Join-Path -Path $ProgramDataRoot -ChildPath 'Config\litellm.config.yaml'))

    $ollama = Get-EAIServiceDefinition -ServiceName $OllamaServiceName
    if ($null -eq $ollama -or $ollama.PathName -ne $ollamaExpectedPath) {
        New-EAIOllamaService -ServiceName $OllamaServiceName -ExecutablePath $ollamaPath -ServiceAccountName $ServiceAccountName -Password $Password | Out-Null
    }

    $lite = Get-EAIServiceDefinition -ServiceName $LiteLLMServiceName
    if ($null -eq $lite -or $lite.PathName -ne $liteExpectedPath) {
        New-EAILiteLLMService -ServiceName $LiteLLMServiceName -PythonPath $pythonPath -ProgramDataRoot $ProgramDataRoot -ServiceAccountName $ServiceAccountName -Password $Password | Out-Null
    }

    Set-Service -Name $OllamaServiceName -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name $LiteLLMServiceName -StartupType Automatic -ErrorAction SilentlyContinue
    return $true
}

Export-ModuleMember -Function New-EAIOllamaService, New-EAILiteLLMService, Set-EAIServiceRecovery, Start-EAIService, Stop-EAIService, Remove-EAIService, Test-EAIServiceExists, Test-EAIServiceRunning, Repair-EAIServices
