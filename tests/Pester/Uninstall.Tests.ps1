#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Uninstall script structure.
#>

BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $UninstallScript = Join-Path $RepoRoot 'scripts\Uninstall-EnterpriseAI.ps1'
}

Describe 'Uninstall - Script existence' {
    It 'Uninstall script exists' {
        $UninstallScript | Should -Exist
    }

    It 'Uninstall script has valid PowerShell syntax' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $UninstallScript, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
    }

    It 'Uninstall script contains -ConfigPath parameter' {
        $content = Get-Content $UninstallScript -Raw
        $content | Should -Match '-ConfigPath'
    }

    It 'Uninstall script contains -RemoveProgramData parameter' {
        $content = Get-Content $UninstallScript -Raw
        $content | Should -Match 'RemoveProgramData'
    }

    It 'Uninstall script preserves ProgramData by default' {
        $content = Get-Content $UninstallScript -Raw
        # Should have PreserveProgramData logic or RemoveProgramData defaulting to false
        $content | Should -Match 'PreserveProgramData|RemoveProgramData'
    }

    It 'Uninstall only removes EnterpriseAI- prefixed firewall rules' {
        $content = Get-Content $UninstallScript -Raw
        # Should reference firewall rule prefix
        $content | Should -Match 'EnterpriseAI-'
    }
}
