#Requires -Version 5.1
Set-StrictMode -Version Latest

function New-EAIAccessRuleSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Identity,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Security.AccessControl.FileSystemRights]$Rights
    )

    return [pscustomobject]@{
        Identity          = $Identity
        Rights            = $Rights
        InheritanceFlags  = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        PropagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    }
}

function Get-EAIAclSpecification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('InstallRoot', 'ProgramData', 'Secrets', 'Logs', 'Models')]
        [string]$Profile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName
    )

    $serviceIdentity = '{0}\{1}' -f $env:COMPUTERNAME, $ServiceAccountName
    switch ($Profile) {
        'InstallRoot' {
            return @(
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Administrators' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity 'NT AUTHORITY\SYSTEM' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity $serviceIdentity -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute),
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Users' -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            )
        }
        'ProgramData' {
            return @(
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Administrators' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity 'NT AUTHORITY\SYSTEM' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity $serviceIdentity -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute),
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Users' -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            )
        }
        'Secrets' {
            return @(
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Administrators' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity 'NT AUTHORITY\SYSTEM' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity $serviceIdentity -Rights ([System.Security.AccessControl.FileSystemRights]::Read)
            )
        }
        'Logs' {
            return @(
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Administrators' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity 'NT AUTHORITY\SYSTEM' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity $serviceIdentity -Rights ([System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Write, Synchronize'),
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Users' -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            )
        }
        'Models' {
            return @(
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Administrators' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity 'NT AUTHORITY\SYSTEM' -Rights ([System.Security.AccessControl.FileSystemRights]::FullControl),
                New-EAIAccessRuleSpec -Identity $serviceIdentity -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute),
                New-EAIAccessRuleSpec -Identity 'BUILTIN\Users' -Rights ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            )
        }
    }
}

function Set-EAIAclProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('InstallRoot', 'ProgramData', 'Secrets', 'Logs', 'Models')]
        [string]$Profile,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)

    foreach ($spec in (Get-EAIAclSpecification -Profile $Profile -ServiceAccountName $ServiceAccountName)) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $spec.Identity,
            $spec.Rights,
            $spec.InheritanceFlags,
            $spec.PropagationFlags,
            $spec.AccessControlType
        )
        $acl.AddAccessRule($rule) | Out-Null
    }

    Set-Acl -Path $Path -AclObject $acl
    return $true
}

function Set-EAIInstallRootAcl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$InstallRoot = 'C:\Program Files\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIAclProfile -Path $InstallRoot -Profile InstallRoot -ServiceAccountName $ServiceAccountName
}

function Set-EAIProgramDataAcl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIAclProfile -Path $ProgramDataRoot -Profile ProgramData -ServiceAccountName $ServiceAccountName
}

function Set-EAISecretsAcl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SecretsPath = 'C:\ProgramData\EnterpriseAI\Secrets',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIAclProfile -Path $SecretsPath -Profile Secrets -ServiceAccountName $ServiceAccountName
}

function Set-EAILogsAcl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogsPath = 'C:\ProgramData\EnterpriseAI\Logs',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIAclProfile -Path $LogsPath -Profile Logs -ServiceAccountName $ServiceAccountName
}

function Set-EAIModelsAcl {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ModelsPath = 'C:\ProgramData\EnterpriseAI\Models',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIAclProfile -Path $ModelsPath -Profile Models -ServiceAccountName $ServiceAccountName
}

function Test-EAIAclCompliant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('InstallRoot', 'ProgramData', 'Secrets', 'Logs', 'Models')]
        [string]$Profile,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{ Path = $Path; Profile = $Profile; State = 'FAIL'; Message = 'Directory is missing.' }
    }

    $acl = Get-Acl -Path $Path
    $rules = @($acl.Access)
    $expectedRules = Get-EAIAclSpecification -Profile $Profile -ServiceAccountName $ServiceAccountName

    foreach ($expected in $expectedRules) {
        $matches = $rules | Where-Object {
            $_.IdentityReference.Value -eq $expected.Identity -and
            $_.AccessControlType -eq $expected.AccessControlType -and
            (($_.FileSystemRights -band $expected.Rights) -eq $expected.Rights)
        }

        if (-not $matches) {
            return [pscustomobject]@{ Path = $Path; Profile = $Profile; State = 'FAIL'; Message = ('Missing expected ACL for {0}.' -f $expected.Identity) }
        }
    }

    $userRules = $rules | Where-Object { $_.IdentityReference.Value -eq 'BUILTIN\Users' -and $_.AccessControlType -eq 'Allow' }
    foreach ($userRule in $userRules) {
        if (($userRule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]'Write, Modify, FullControl, CreateFiles, AppendData') -ne 0) {
            return [pscustomobject]@{ Path = $Path; Profile = $Profile; State = 'FAIL'; Message = 'Users group has write-capable access.' }
        }
    }

    if ($Profile -eq 'Secrets' -and $userRules.Count -gt 0) {
        return [pscustomobject]@{ Path = $Path; Profile = $Profile; State = 'FAIL'; Message = 'Secrets directory must not grant Users access.' }
    }

    return [pscustomobject]@{ Path = $Path; Profile = $Profile; State = 'PASS'; Message = 'ACL matches the expected baseline.' }
}

function Repair-EAIAcls {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$InstallRoot = 'C:\Program Files\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ProgramDataRoot = 'C:\ProgramData\EnterpriseAI',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName = 'svc_EnterpriseAI'
    )

    Set-EAIInstallRootAcl -InstallRoot $InstallRoot -ServiceAccountName $ServiceAccountName | Out-Null
    Set-EAIProgramDataAcl -ProgramDataRoot $ProgramDataRoot -ServiceAccountName $ServiceAccountName | Out-Null
    Set-EAISecretsAcl -SecretsPath (Join-Path -Path $ProgramDataRoot -ChildPath 'Secrets') -ServiceAccountName $ServiceAccountName | Out-Null
    Set-EAILogsAcl -LogsPath (Join-Path -Path $ProgramDataRoot -ChildPath 'Logs') -ServiceAccountName $ServiceAccountName | Out-Null
    Set-EAIModelsAcl -ModelsPath (Join-Path -Path $ProgramDataRoot -ChildPath 'Models') -ServiceAccountName $ServiceAccountName | Out-Null
    return $true
}

Export-ModuleMember -Function Set-EAIInstallRootAcl, Set-EAIProgramDataAcl, Set-EAISecretsAcl, Set-EAILogsAcl, Set-EAIModelsAcl, Test-EAIAclCompliant, Repair-EAIAcls
