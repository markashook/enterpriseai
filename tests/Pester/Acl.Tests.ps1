#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for EnterpriseAI ACL module.
#>

# Path variables are defined at script level so they are available during Pester 5's
# discovery phase, when -Skip: conditions are evaluated (before BeforeAll runs).
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ModulePath = Join-Path $RepoRoot 'scripts\modules\EnterpriseAI.Acl.psm1'

BeforeAll {
    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force
    }
}

Describe 'ACL - Module' {
    It 'ACL module file exists' {
        $ModulePath | Should -Exist
    }

    It 'Module can be imported without errors' -Skip:(!(Test-Path $ModulePath)) {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'Set-EAIInstallRootAcl function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAIInstallRootAcl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAIProgramDataAcl function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAIProgramDataAcl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAISecretsAcl function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAISecretsAcl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAILogsAcl function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAILogsAcl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Set-EAIModelsAcl function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Set-EAIModelsAcl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Test-EAIAclCompliant function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Test-EAIAclCompliant -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Repair-EAIAcls function exists' -Skip:(!(Test-Path $ModulePath)) {
        Get-Command -Name Repair-EAIAcls -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
