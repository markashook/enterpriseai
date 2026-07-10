#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for EnterpriseAI Services module.
#>

# Computed at script level so that -Skip: conditions can reference $ModulePath during
# Pester's discovery phase (BeforeAll has not yet run at that point).
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ModulePath = Join-Path $RepoRoot 'scripts\modules\EnterpriseAI.Services.psm1'

BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModulePath = Join-Path $RepoRoot 'scripts\modules\EnterpriseAI.Services.psm1'

    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force
    }
}

Describe 'Services - Module' {
    It 'Services module file exists' {
        $ModulePath | Should -Exist
    }

    It 'Module can be imported without errors' -Skip:(!(Test-Path $ModulePath)) {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'New-EAIOllamaService function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name New-EAIOllamaService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'New-EAILiteLLMService function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name New-EAILiteLLMService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAIServiceRecovery function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAIServiceRecovery -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Start-EAIService function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Start-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Stop-EAIService function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Stop-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Remove-EAIService function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Remove-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIServiceExists function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Test-EAIServiceExists -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIServiceRunning function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Test-EAIServiceRunning -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Repair-EAIServices function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Repair-EAIServices -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Services - Config values' {
    It 'Config OllamaServiceName is EnterpriseAI-Ollama' {
        $configPath = Join-Path $RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.OllamaServiceName | Should -Be 'EnterpriseAI-Ollama'
    }

    It 'Config LiteLLMServiceName is EnterpriseAI-LiteLLM' {
        $configPath = Join-Path $RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.LiteLLMServiceName | Should -Be 'EnterpriseAI-LiteLLM'
    }
}
