#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:EAIServiceLogonRight = 'SeServiceLogonRight'
$script:EAIInteractiveDenyRights = @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight')

function ConvertTo-EAIPlainText {
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

function Get-EAILocalUserObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName
    )

    if (Get-Command -Name Get-LocalUser -ErrorAction SilentlyContinue) {
        return Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    }

    try {
        $account = [ADSI]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $AccountName)
        $null = $account.Name
        return $account
    }
    catch {
        return $null
    }
}

function Get-EAIAccountSid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName
    )

    $account = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $AccountName)
    return $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Set-EAILsaRight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Right
    )

    $workingDirectory = Join-Path -Path ${env:ProgramData} -ChildPath 'EnterpriseAI\Temp'
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    }

    $sid = Get-EAIAccountSid -AccountName $AccountName
    $cfgPath = Join-Path -Path $workingDirectory -ChildPath ('{0}.inf' -f $Right)
    $dbPath = Join-Path -Path $workingDirectory -ChildPath ('{0}.sdb' -f $Right)

    & secedit.exe /export /cfg $cfgPath /areas USER_RIGHTS | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        throw ('Failed to export local security policy for right {0}.' -f $Right)
    }

    $content = Get-Content -LiteralPath $cfgPath -ErrorAction Stop
    $marker = '{0} = ' -f $Right
    $updated = $false

    for ($index = 0; $index -lt $content.Count; $index++) {
        if ($content[$index] -like ($marker + '*')) {
            $currentValues = @()
            $currentText = $content[$index].Substring($marker.Length).Trim()
            if (-not [string]::IsNullOrWhiteSpace($currentText)) {
                $currentValues = $currentText.Split(',')
            }

            if ($currentValues -notcontains ('*' + $sid)) {
                $currentValues += ('*' + $sid)
            }

            $content[$index] = $marker + ($currentValues -join ',')
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $content += ($marker + '*' + $sid)
    }

    Set-Content -LiteralPath $cfgPath -Value $content -Encoding Unicode -Force
    & secedit.exe /configure /db $dbPath /cfg $cfgPath /areas USER_RIGHTS | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ('Failed to assign local security right {0} to {1}.' -f $Right, $AccountName)
    }
}

function Test-EAIServiceAccountExists {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI'
    )

    return ($null -ne (Get-EAILocalUserObject -AccountName $AccountName))
}

function New-EAIServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI',

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Description = 'EnterpriseAI local runtime service account'
    )

    if (Test-EAIServiceAccountExists -AccountName $AccountName) {
        return Get-EAILocalUserObject -AccountName $AccountName
    }

    if ($null -eq $Password) {
        throw 'A SecureString password is required. Do not hardcode or log service account passwords.'
    }

    if (Get-Command -Name New-LocalUser -ErrorAction SilentlyContinue) {
        $user = New-LocalUser -Name $AccountName -Password $Password -FullName $AccountName -Description $Description -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires
    }
    else {
        $plainText = ConvertTo-EAIPlainText -SecureString $Password
        $computer = [ADSI]('WinNT://{0},computer' -f $env:COMPUTERNAME)
        $user = $computer.Create('user', $AccountName)
        $user.SetPassword($plainText)
        $user.Put('Description', $Description)
        $user.SetInfo()
        $userFlags = 0x10000
        $user.Put('UserFlags', $userFlags)
        $user.SetInfo()
    }

    Grant-EAIServiceAccountLsaRight -AccountName $AccountName
    Deny-EAIServiceAccountInteractiveLogon -AccountName $AccountName
    return Get-EAILocalUserObject -AccountName $AccountName
}

function Repair-EAIServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI',

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.SecureString]$Password
    )

    if (-not (Test-EAIServiceAccountExists -AccountName $AccountName)) {
        return New-EAIServiceAccount -AccountName $AccountName -Password $Password
    }

    if (Get-Command -Name Set-LocalUser -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $AccountName -PasswordNeverExpires $true -UserMayChangePassword $false -Description 'EnterpriseAI local runtime service account' -ErrorAction Stop
        Enable-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    }

    Grant-EAIServiceAccountLsaRight -AccountName $AccountName
    Deny-EAIServiceAccountInteractiveLogon -AccountName $AccountName
    return Get-EAILocalUserObject -AccountName $AccountName
}

function Grant-EAIServiceAccountLsaRight {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI'
    )

    if (-not (Test-EAIServiceAccountExists -AccountName $AccountName)) {
        throw ('Service account not found: {0}' -f $AccountName)
    }

    Set-EAILsaRight -AccountName $AccountName -Right $script:EAIServiceLogonRight
}

function Deny-EAIServiceAccountInteractiveLogon {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI'
    )

    foreach ($right in $script:EAIInteractiveDenyRights) {
        try {
            Set-EAILsaRight -AccountName $AccountName -Right $right
        }
        catch {
            Write-Warning ('Unable to assign {0} to {1}: {2}' -f $right, $AccountName, $_.Exception.Message)
        }
    }
}

function Disable-EAIServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI'
    )

    if (-not (Test-EAIServiceAccountExists -AccountName $AccountName)) {
        return $false
    }

    if (Get-Command -Name Disable-LocalUser -ErrorAction SilentlyContinue) {
        Disable-LocalUser -Name $AccountName -ErrorAction Stop
    }
    else {
        $user = Get-EAILocalUserObject -AccountName $AccountName
        $flags = [int]$user.UserFlags.Value
        $user.Put('UserFlags', ($flags -bor 0x0002))
        $user.SetInfo()
    }

    return $true
}

function Test-EAIServiceAccountIsNonAdmin {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$AccountName = 'svc_EnterpriseAI'
    )

    if (-not (Test-EAIServiceAccountExists -AccountName $AccountName)) {
        return $false
    }

    if (Get-Command -Name Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        $members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object -ExpandProperty Name
        return ($members -notcontains ('{0}\{1}' -f $env:COMPUTERNAME, $AccountName))
    }

    $group = [ADSI]('WinNT://{0}/Administrators,group' -f $env:COMPUTERNAME)
    $names = @($group.psbase.Invoke('Members')) | ForEach-Object {
        $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
    }
    return ($names -notcontains $AccountName)
}

Export-ModuleMember -Function New-EAIServiceAccount, Repair-EAIServiceAccount, Grant-EAIServiceAccountLsaRight, Deny-EAIServiceAccountInteractiveLogon, Disable-EAIServiceAccount, Test-EAIServiceAccountExists, Test-EAIServiceAccountIsNonAdmin
