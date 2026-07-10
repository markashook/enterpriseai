#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:EAILogFilePath = $null
$script:EAILogWriter = $null
$script:EAILogInitialized = $false
$script:EAILogLevels = @('INFO', 'WARN', 'ERROR', 'DEBUG')

function Protect-EAILogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $sanitized = $Message
    $patterns = @(
        '(?i)(api[_-]?key\s*[:=]\s*)([^;\s]+)',
        '(?i)(password\s*[:=]\s*)([^;\s]+)',
        '(?i)(secret\s*[:=]\s*)([^;\s]+)',
        '(?i)(token\s*[:=]\s*)([^;\s]+)',
        '(?i)(authorization\s*[:=]\s*bearer\s+)([^;\s]+)'
    )

    foreach ($pattern in $patterns) {
        $sanitized = [System.Text.RegularExpressions.Regex]::Replace(
            $sanitized,
            $pattern,
            '$1[REDACTED]'
        )
    }

    return $sanitized.Replace([Environment]::NewLine, ' ')
}

function Initialize-EAILog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogFileName = 'EnterpriseAI.log',

        [Parameter()]
        [switch]$Force
    )

    if ($script:EAILogInitialized -and -not $Force.IsPresent) {
        return $script:EAILogFilePath
    }

    if ($script:EAILogInitialized -and $Force.IsPresent) {
        Close-EAILog
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $script:EAILogFilePath = Join-Path -Path $LogDirectory -ChildPath $LogFileName
    $fileMode = [System.IO.FileMode]::Append
    if ($Force.IsPresent -and -not (Test-Path -LiteralPath $script:EAILogFilePath -PathType Leaf)) {
        $fileMode = [System.IO.FileMode]::Create
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $stream = New-Object System.IO.FileStream(
        $script:EAILogFilePath,
        $fileMode,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
    $writer = New-Object System.IO.StreamWriter($stream, $encoding)
    $writer.AutoFlush = $true

    $script:EAILogWriter = $writer
    $script:EAILogInitialized = $true

    Write-EAILog -Severity INFO -Message ('Initialized log file at {0}' -f $script:EAILogFilePath)
    return $script:EAILogFilePath
}

function Write-EAILog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($script:EAILogLevels -notcontains $Severity) {
        throw 'Unsupported log severity.'
    }

    $timestamp = [DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:ss.fffK')
    $safeMessage = Protect-EAILogMessage -Message $Message
    $entry = '{0} [{1}] {2}' -f $timestamp, $Severity, $safeMessage

    switch ($Severity) {
        'ERROR' { Write-Error -Message $safeMessage -ErrorAction Continue }
        'WARN'  { Write-Warning -Message $safeMessage }
        'DEBUG' { Write-Verbose -Message $safeMessage -Verbose }
        default { Write-Host $entry }
    }

    if ($Severity -eq 'DEBUG') {
        Write-Host $entry
    }

    if ($script:EAILogInitialized -and $null -ne $script:EAILogWriter) {
        $script:EAILogWriter.WriteLine($entry)
    }
}

function Close-EAILog {
    [CmdletBinding()]
    param()

    if ($script:EAILogInitialized -and $null -ne $script:EAILogWriter) {
        try {
            $script:EAILogWriter.Flush()
            $script:EAILogWriter.Dispose()
        }
        finally {
            $script:EAILogWriter = $null
            $script:EAILogInitialized = $false
        }
    }

    if ($null -ne $script:EAILogFilePath) {
        Write-Host ('Closed log file {0}' -f $script:EAILogFilePath)
    }
}

Export-ModuleMember -Function Initialize-EAILog, Write-EAILog, Close-EAILog
