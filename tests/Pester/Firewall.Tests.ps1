#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for EnterpriseAI firewall module.
#>

$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ModulePath = Join-Path $script:RepoRoot 'scripts\modules\EnterpriseAI.Firewall.psm1'

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\modules\EnterpriseAI.Firewall.psm1'
    $FirewallPolicy = Join-Path $script:RepoRoot 'config\firewall.policy.json'

    if (Test-Path $script:ModulePath) {
        Import-Module $script:ModulePath -Force
    }
}

Describe 'Firewall - Policy file' {
    It 'Firewall policy file exists' {
        $FirewallPolicy | Should -Exist
    }

    It 'Firewall policy is valid JSON' {
        { Get-Content $FirewallPolicy -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'All firewall rule names use EnterpriseAI- prefix' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        foreach ($rule in $policy.Rules) {
            $rule.Name | Should -BeLike 'EnterpriseAI-*' -Because "all package firewall rules must use the EnterpriseAI- prefix"
        }
    }

    It 'Firewall policy has LiteLLM inbound block rule' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        $litellmBlockRule = $policy.Rules | Where-Object {
            $_.Name -like '*LiteLLM*Inbound*Block*' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block'
        }
        $litellmBlockRule | Should -Not -BeNullOrEmpty
    }

    It 'Firewall policy has Ollama inbound block rule' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        $ollamaBlockRule = $policy.Rules | Where-Object {
            $_.Name -like '*Ollama*Inbound*Block*' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block'
        }
        $ollamaBlockRule | Should -Not -BeNullOrEmpty
    }

    It 'Firewall policy has Ollama outbound block rule' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        $ollamaOutboundBlock = $policy.Rules | Where-Object {
            $_.Name -like '*Ollama*Outbound*Block*' -and $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block'
        }
        $ollamaOutboundBlock | Should -Not -BeNullOrEmpty
    }

    It 'LiteLLM rules target port 4000' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        $litellmRules = $policy.Rules | Where-Object { $_.Name -like '*LiteLLM*' }
        $litellmRules | Should -Not -BeNullOrEmpty
        foreach ($rule in $litellmRules) {
            if ($rule.LocalPort) {
                $rule.LocalPort | Should -Be 4000
            }
        }
    }

    It 'Ollama inbound rules target port 11434' {
        $policy = Get-Content $FirewallPolicy -Raw | ConvertFrom-Json
        $ollamaInboundRules = $policy.Rules | Where-Object {
            $_.Name -like '*Ollama*' -and $_.Direction -eq 'Inbound' -and $_.LocalPort
        }
        foreach ($rule in $ollamaInboundRules) {
            $rule.LocalPort | Should -Be 11434
        }
    }
}

Describe 'Firewall - Module' {
    It 'Firewall module file exists' {
        $script:ModulePath | Should -Exist
    }

    It 'Module can be imported without errors' -Skip:(!(Test-Path $script:ModulePath)) {
        { Import-Module $script:ModulePath -Force } | Should -Not -Throw
    }

    It 'New-EAIFirewallRules function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name New-EAIFirewallRules -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIFirewallRules function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Test-EAIFirewallRules -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Repair-EAIFirewallRules function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Repair-EAIFirewallRules -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Remove-EAIFirewallRules function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Remove-EAIFirewallRules -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Firewall - Security requirements' {
    It 'Config default endpoints are loopback-only' {
        $configPath = Join-Path $script:RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.LiteLLMEndpoint | Should -Match '^http://127\.'
        $config.OllamaEndpoint | Should -Match '^http://127\.'
    }

    It 'Config RuntimeModelPullsEnabled is false by default' {
        $configPath = Join-Path $script:RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.RuntimeModelPullsEnabled | Should -Be $false
    }
}
