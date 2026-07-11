#Requires -Version 5.1
Set-StrictMode -Version Latest

# Windows Firewall cannot perfectly guarantee per-process loopback isolation in every configuration.
# The primary protection for this package is the explicit loopback-only binding on the services.

function Get-EAIFirewallRuleDefinitions {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'EnterpriseAI-',

        [Parameter()]
        [AllowNull()]
        [string]$OllamaProgramPath
    )

    $rules = @(
        [ordered]@{ Name = $Prefix + 'LiteLLM-Inbound-Block-NonLoopback'; Direction = 'Inbound'; Action = 'Block'; Protocol = 'TCP'; LocalPort = '4000'; RemoteAddress = 'Any'; Description = 'Block non-loopback inbound traffic to LiteLLM. Loopback binding remains the primary protection.' },
        [ordered]@{ Name = $Prefix + 'LiteLLM-Inbound-Allow-Loopback'; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'TCP'; LocalPort = '4000'; RemoteAddress = '127.0.0.1'; Description = 'Allow loopback traffic to LiteLLM.' },
        [ordered]@{ Name = $Prefix + 'Ollama-Inbound-Block-NonLoopback'; Direction = 'Inbound'; Action = 'Block'; Protocol = 'TCP'; LocalPort = '11434'; RemoteAddress = 'Any'; Description = 'Block non-loopback inbound traffic to Ollama. Loopback binding remains the primary protection.' },
        [ordered]@{ Name = $Prefix + 'Ollama-Inbound-Allow-Loopback'; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'TCP'; LocalPort = '11434'; RemoteAddress = '127.0.0.2'; Description = 'Allow loopback traffic to Ollama.' },
        [ordered]@{ Name = $Prefix + 'Ollama-Outbound-Block-Internet'; Direction = 'Outbound'; Action = 'Block'; Protocol = 'TCP'; RemotePort = '80,443'; RemoteAddress = 'Any'; Description = 'Block Ollama outbound internet access to prevent arbitrary model pulls.' }
    )

    if (-not [string]::IsNullOrWhiteSpace($OllamaProgramPath)) {
        foreach ($rule in $rules | Where-Object { $_.Name -like ($Prefix + 'Ollama-*') }) {
            $rule.Program = $OllamaProgramPath
        }
    }

    return $rules
}

function New-EAIFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'EnterpriseAI-',

        [Parameter()]
        [AllowNull()]
        [string]$OllamaProgramPath = 'C:\Program Files\EnterpriseAI\Runtime\ollama.exe'
    )

    foreach ($definition in (Get-EAIFirewallRuleDefinitions -Prefix $Prefix -OllamaProgramPath $OllamaProgramPath)) {
        if (-not (Get-NetFirewallRule -DisplayName $definition.Name -ErrorAction SilentlyContinue)) {
            $splat = @{
                DisplayName = $definition.Name
                Direction   = $definition.Direction
                Action      = $definition.Action
                Protocol    = $definition.Protocol
                Description = $definition.Description
                Enabled     = 'True'
                Profile     = 'Any'
            }

            if ($definition.ContainsKey('LocalPort')) {
                $splat['LocalPort'] = $definition.LocalPort
            }

            if ($definition.ContainsKey('RemotePort')) {
                $splat['RemotePort'] = $definition.RemotePort
            }

            if ($definition.ContainsKey('RemoteAddress')) {
                $splat['RemoteAddress'] = $definition.RemoteAddress
            }

            if ($definition.ContainsKey('Program')) {
                $splat['Program'] = $definition.Program
            }

            New-NetFirewallRule @splat | Out-Null
        }
    }

    return $true
}

function Test-EAIFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'EnterpriseAI-'
    )

    $result = [ordered]@{}
    foreach ($definition in (Get-EAIFirewallRuleDefinitions -Prefix $Prefix)) {
        $rule = Get-NetFirewallRule -DisplayName $definition.Name -ErrorAction SilentlyContinue
        if ($null -eq $rule) {
            $result[$definition.Name] = [pscustomobject]@{ State = 'FAIL'; Message = 'Firewall rule is missing.' }
        }
        else {
            $result[$definition.Name] = [pscustomobject]@{ State = 'PASS'; Message = 'Firewall rule is present.' }
        }
    }

    $result['LoopbackIsolationNote'] = [pscustomobject]@{
        State   = 'WARN'
        Message = 'Windows Firewall may not perfectly enforce per-process loopback isolation. Loopback binding is the primary control.'
    }
    return $result
}

function Repair-EAIFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'EnterpriseAI-',

        [Parameter()]
        [AllowNull()]
        [string]$OllamaProgramPath = 'C:\Program Files\EnterpriseAI\Runtime\ollama.exe'
    )

    $status = Test-EAIFirewallRules -Prefix $Prefix
    $missing = @($status.GetEnumerator() | Where-Object { $_.Key -ne 'LoopbackIsolationNote' -and $_.Value.State -eq 'FAIL' })
    if ($missing.Count -gt 0) {
        New-EAIFirewallRules -Prefix $Prefix -OllamaProgramPath $OllamaProgramPath | Out-Null
    }

    return (Test-EAIFirewallRules -Prefix $Prefix)
}

function Remove-EAIFirewallRules {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = 'EnterpriseAI-'
    )

    $rules = Get-NetFirewallRule -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like ($Prefix + '*') }
    foreach ($rule in $rules) {
        Remove-NetFirewallRule -Name $rule.Name | Out-Null
    }

    return $true
}

Export-ModuleMember -Function New-EAIFirewallRules, Test-EAIFirewallRules, Repair-EAIFirewallRules, Remove-EAIFirewallRules
