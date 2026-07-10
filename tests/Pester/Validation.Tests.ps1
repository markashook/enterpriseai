#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for EnterpriseAI.Config module and config parsing.
#>

# Path variables are defined at script level so they are available during Pester 5's
# discovery phase, when -Skip: conditions are evaluated (before BeforeAll runs).
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ModulePath = Join-Path $RepoRoot 'scripts\modules\EnterpriseAI.Config.psm1'
$ValidFixture = Join-Path $RepoRoot 'tests\fixtures\package-config.valid.json'
$InvalidFixture = Join-Path $RepoRoot 'tests\fixtures\package-config.invalid.json'

BeforeAll {
    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force
    }
}

Describe 'Config - Valid fixture' {
    It 'Valid config fixture is valid JSON' {
        { Get-Content $ValidFixture -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Valid config has required fields' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.PackageName | Should -Not -BeNullOrEmpty
        $config.InstallRoot | Should -Not -BeNullOrEmpty
        $config.ProgramDataRoot | Should -Not -BeNullOrEmpty
        $config.ServiceAccountName | Should -Not -BeNullOrEmpty
        $config.OllamaServiceName | Should -Not -BeNullOrEmpty
        $config.LiteLLMServiceName | Should -Not -BeNullOrEmpty
    }

    It 'Valid config LiteLLMEndpoint is loopback-only' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.LiteLLMEndpoint | Should -Match '^http://127\.'
    }

    It 'Valid config OllamaEndpoint is loopback-only' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.OllamaEndpoint | Should -Match '^http://127\.'
    }

    It 'Valid config RuntimeModelPullsEnabled defaults to false' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.RuntimeModelPullsEnabled | Should -Be $false
    }

    It 'Valid config RequireLiteLLMApiKey defaults to true' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.RequireLiteLLMApiKey | Should -Be $true
    }

    It 'Valid config PreserveProgramDataOnUninstall defaults to true' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.PreserveProgramDataOnUninstall | Should -Be $true
    }

    It 'Valid config FirewallRulePrefix starts with EnterpriseAI-' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.FirewallRulePrefix | Should -BeLike 'EnterpriseAI-*'
    }
}

Describe 'Config - Invalid fixture' {
    It 'Invalid config fixture is valid JSON' {
        { Get-Content $InvalidFixture -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Invalid config has non-loopback LiteLLMEndpoint' {
        $config = Get-Content $InvalidFixture -Raw | ConvertFrom-Json
        $config.LiteLLMEndpoint | Should -Not -Match '^http://127\.'
    }

    It 'Invalid config has non-loopback OllamaEndpoint' {
        $config = Get-Content $InvalidFixture -Raw | ConvertFrom-Json
        $config.OllamaEndpoint | Should -Not -Match '^http://127\.'
    }

    It 'Invalid config has empty InstallRoot' {
        $config = Get-Content $InvalidFixture -Raw | ConvertFrom-Json
        $config.InstallRoot | Should -BeNullOrEmpty
    }
}

Describe 'Config - EnterpriseAI.Config module' {
    It 'Module file exists' {
        $ModulePath | Should -Exist
    }

    It 'Module can be imported without errors' -Skip:(!(Test-Path $ModulePath)) {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'Read-EAIPackageConfig function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Read-EAIPackageConfig -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIConfigValid function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Test-EAIConfigValid -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Read-EAIPackageConfig returns valid config from valid fixture' -Skip:(!(Test-Path $ModulePath)) {
        $result = Read-EAIPackageConfig -ConfigPath $ValidFixture
        $result | Should -Not -BeNullOrEmpty
        $result.PackageName | Should -Not -BeNullOrEmpty
    }
}

Describe 'Config - Approved models fixture' {
    It 'Approved models fixture is valid JSON' {
        $fixture = Join-Path $RepoRoot 'tests\fixtures\approved-models.valid.json'
        { Get-Content $fixture -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Approved models fixture has Models array' {
        $fixture = Join-Path $RepoRoot 'tests\fixtures\approved-models.valid.json'
        $models = (Get-Content $fixture -Raw | ConvertFrom-Json).Models
        $models | Should -Not -BeNullOrEmpty
        $models.Count | Should -BeGreaterThan 0
    }

    It 'All model aliases are non-empty' {
        $fixture = Join-Path $RepoRoot 'tests\fixtures\approved-models.valid.json'
        $models = (Get-Content $fixture -Raw | ConvertFrom-Json).Models
        foreach ($model in $models) {
            $model.Alias | Should -Not -BeNullOrEmpty
        }
    }
}
