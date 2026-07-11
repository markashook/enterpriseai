#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for EnterpriseAI Services module.
#>

$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:ModulePath = Join-Path $script:RepoRoot 'scripts\modules\EnterpriseAI.Services.psm1'

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\modules\EnterpriseAI.Services.psm1'
    if (Test-Path $script:ModulePath) {
        Import-Module $script:ModulePath -Force
    }
}

Describe 'Services - Module' {
    It 'Services module file exists' {
        $script:ModulePath | Should -Exist
    }

    It 'Module can be imported without errors' -Skip:(!(Test-Path $script:ModulePath)) {
        { Import-Module $script:ModulePath -Force } | Should -Not -Throw
    }

    It 'New-EAIOllamaService function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name New-EAIOllamaService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'New-EAILiteLLMService function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name New-EAILiteLLMService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAIServiceRecovery function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Set-EAIServiceRecovery -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Start-EAIService function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Start-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Stop-EAIService function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Stop-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Remove-EAIService function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Remove-EAIService -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIServiceExists function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Test-EAIServiceExists -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIServiceRunning function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Test-EAIServiceRunning -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Repair-EAIServices function exists' -Skip:(!(Test-Path $script:ModulePath)) {
        Get-Command -Name Repair-EAIServices -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Services - Config values' {
    It 'Config OllamaServiceName is EnterpriseAI-Ollama' {
        $configPath = Join-Path $script:RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.OllamaServiceName | Should -Be 'EnterpriseAI-Ollama'
    }

    It 'Config LiteLLMServiceName is EnterpriseAI-LiteLLM' {
        $configPath = Join-Path $script:RepoRoot 'config\enterpriseai.package.json'
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $config.LiteLLMServiceName | Should -Be 'EnterpriseAI-LiteLLM'
    }
}
