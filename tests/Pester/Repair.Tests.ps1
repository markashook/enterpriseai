#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Repair script structure.
#>

BeforeAll {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $RepairScript = Join-Path $RepoRoot 'scripts\Repair-EnterpriseAI.ps1'
}

Describe 'Repair - Script existence' {
    It 'Repair script exists' {
        $RepairScript | Should -Exist
    }

    It 'Repair script has valid PowerShell syntax' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $RepairScript, [ref]$null, [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
    }

    It 'Repair script contains -ConfigPath parameter' {
        $content = Get-Content $RepairScript -Raw
        $content | Should -Match '-ConfigPath'
    }

    It 'Repair script does not download from internet' {
        $lines = Get-Content $RepairScript
        $downloadLines = $lines | Where-Object {
            $_ -notmatch '^\s*#' -and
            $_ -match 'Invoke-WebRequest|\.DownloadFile\(' -and
            ($_ -notmatch 'Invoke-WebRequest' -or $_ -match '\s-OutFile\s' -or $_ -match "-Uri\s+['""]https?://(?!localhost|127\.|::1)")
        }
        $downloadLines | Should -BeNullOrEmpty
    }
}
