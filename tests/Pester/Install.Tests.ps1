#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Install script structure and module availability.
    These are scaffold tests that verify script and module existence/syntax.
    Full install behavior tests require a Windows environment with administrative privileges.
#>

BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $InstallScript = Join-Path $RepoRoot 'scripts\Install-EnterpriseAI.ps1'
    $ValidFixture = Join-Path $RepoRoot 'tests\fixtures\package-config.valid.json'
}

Describe 'Install - Script existence' {
    It 'Install script exists' {
        $InstallScript | Should -Exist
    }

    It 'Install script has valid PowerShell syntax' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $InstallScript, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
    }

    It 'Install script contains -ConfigPath parameter' {
        $content = Get-Content $InstallScript -Raw
        $content | Should -Match '-ConfigPath'
    }

    It 'Install script does not contain Invoke-WebRequest' {
        $lines = Get-Content $InstallScript
        $downloadLines = $lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'Invoke-WebRequest' }
        $downloadLines | Should -BeNullOrEmpty -Because 'install scripts must not download from internet at install time'
    }

    It 'Install script does not contain WebClient download calls' {
        $lines = Get-Content $InstallScript
        $downloadLines = $lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\.DownloadFile\(' }
        $downloadLines | Should -BeNullOrEmpty -Because 'install scripts must not download from internet at install time'
    }
}

Describe 'Install - Required modules' {
    $modules = @(
        'EnterpriseAI.Logging.psm1',
        'EnterpriseAI.Config.psm1',
        'EnterpriseAI.Accounts.psm1',
        'EnterpriseAI.Acl.psm1',
        'EnterpriseAI.Services.psm1',
        'EnterpriseAI.Secrets.psm1',
        'EnterpriseAI.Firewall.psm1',
        'EnterpriseAI.Validation.psm1'
    )

    foreach ($modFile in $modules) {
        It "Module $modFile exists" {
            $modPath = Join-Path $RepoRoot "scripts\modules\$modFile"
            $modPath | Should -Exist
        }

        It "Module $modFile has valid PowerShell syntax" {
            $modPath = Join-Path $RepoRoot "scripts\modules\$modFile"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $modPath, [ref]$null, [ref]$errors
            )
            $errors | Should -BeNullOrEmpty
        }
    }
}

Describe 'Install - Config validation' {
    It 'Valid fixture passes endpoint loopback check' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.LiteLLMEndpoint | Should -Match '^http://127\.'
        $config.OllamaEndpoint | Should -Match '^http://127\.'
    }

    It 'Valid fixture has RuntimeModelPullsEnabled = false' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.RuntimeModelPullsEnabled | Should -Be $false
    }

    It 'Valid fixture has RequireLiteLLMApiKey = true' {
        $config = Get-Content $ValidFixture -Raw | ConvertFrom-Json
        $config.RequireLiteLLMApiKey | Should -Be $true
    }
}
