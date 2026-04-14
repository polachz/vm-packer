<#
.SYNOPSIS
  Unified deployment logger: writes plain text + JSON logs.
  Transcript and Windows Event Log are optional and separate.

.DESCRIPTION
  Provides Trace-* functions (Trace-Info/Trace-Warning/Trace-Error/Trace-Debug, Trace-Log)
  that write a single entry to:
    - Plain text log file (one line per entry; compact)
    - JSON Lines log file (one JSON object per line; machine-friendly)
    - Console via Information/Verbose streams (optional, concise)
    - Windows Event Log (optional; initialized only when enabled and elevated)

  Transcript is OFF by default; when enabled, it writes to a separate file.

.USAGE
  ===== QUICK START =====

  1. Import with default settings:
     Import-Module .\ps-logger.psm1 -Force
     Trace-Info "Hello from logger"
     # Logs to: C:\ProgramData\DeployLogs\ps-logger.<timestamp>.log

  2. Import with custom configuration (passed at import time):
     Import-Module .\ps-logger.psm1 -Force -ArgumentList @{
         LogDir       = 'C:\MyLogs'
         EnableDebug  = $true
         EnableEventLog = $true
         EventLogName = 'MyApp'
         EventSource  = 'Deployment'
     }
     Trace-Info "Logged with custom config"
     Trace-Debug "This is visible because EnableDebug is true"

  3. Reconfigure logger after import (if needed):
     Import-Module .\ps-logger.psm1 -Force
     Initialize-Logger -Options @{
         LogDir      = 'C:\NewPath'
         EnableDebug = $true
     }
     Trace-Info "Now using new config"

.EXPORTED FUNCTIONS
  - Trace-Log -Level <level> -Message <string> [-Fields <hashtable>]
  - Trace-Info -Message <string> [-Fields <hashtable>]
  - Trace-Warning -Message <string> [-Fields <hashtable>]
  - Trace-Error -Message <string> [-Fields <hashtable>]
  - Trace-Debug -Message <string> [-Fields <hashtable>]
  - Get-LogDir
  - Initialize-Logger -Options <hashtable>


.PARAMETER LogDir
  Base directory for logs (default C:\ProgramData\DeployLogs) used when paths are not explicitly provided.

.PARAMETER LogFileName
  Base name used for Text/JSON files if specific paths not provided. Default: <ScriptName>.<timestamp>.

.PARAMETER TextLogPath
  Full path for the plain text log file. Overrides LogDir/LogFileName.

.PARAMETER JsonLogPath
  Full path for the JSONL log file. Overrides LogDir/LogFileName.

.PARAMETER EnableTranscript
  If set, starts a transcript and writes it to TranscriptPath. Default: off.

.PARAMETER TranscriptPath
  Full path for transcript file. If not provided but -EnableTranscript is set,
  defaults to <LogDir>\<ScriptName>.<timestamp>.transcript.log

.PARAMETER EnableEventLog
  If set, writes entries to Windows Event Log. Default: off.
  Note: Only initializes/uses Event Log when running elevated. Otherwise, warns once.

.PARAMETER EventLogName
  Windows Event Log name (custom log created if absent). Default: Deployment.

.PARAMETER EventSource
  Event Source (created if absent). Default: AutoUnattend.

.PARAMETER CorrelationId
  GUID used to correlate entries across steps/reboots. Default: new GUID.

.PARAMETER ScriptName
  Logical name of the calling script included in each entry.
  NOTE: When dot-sourcing, pass your top-level script name via -ScriptName for accuracy.

.PARAMETER EnableDebug
  If set, DEBUG entries will be emitted to the Verbose stream (visible with -Verbose).

.PARAMETER ConsoleInfo
  If set, INFO/WARN/ERROR messages are also emitted to Information stream (visible by default).

.NOTES
  - Recommended: run elevated for Event Log. Text/JSON logging works without elevation.
  - Text format: [UTC ISO8601] [LEVEL] Message  key=value ...
  - JSON format: one compact object per line; includes metadata and optional Fields (flattened).
  - IMPORTANT: Call Initialize-Logger at most once per session. Multiple initializations change log filenames 
    due to timestamp generation, causing logs to be split across multiple files.
  - Tested on Windows PowerShell 5.1.

.EXAMPLES
  # Trace with optional metadata
  Trace-Info "Process completed" @{ ProcessId=123; Duration="2.5s" }

  # Error with exception details
  try { Invoke-Something } catch { Trace-Error $_.Exception.Message }

  # Debug only visible with -Verbose flag when EnableDebug=$true
  Trace-Debug "Detailed diagnostic info"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ScriptName,
    [Parameter(Mandatory = $false)]
    [hashtable] $ModuleInitParams = $null
)


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# make Information visible by default
$InformationPreference = 'Continue'


# Flag indicating whether Event Log is configured and ready
$script:EventLogReady = $false
$script:TranscriptEnabled = $false
function Initialize-Logger {
    <#
    .SYNOPSIS
      Initialize or reconfigure the logger using a hashtable of options.
    .PARAMETER Options
      Hashtable with optional keys matching module parameters (LogDir, EventLogName, ...)
    #>
    [CmdletBinding()]
    param(
        [hashtable] $Options
    )

    # Define default values
    $defaults = @{
        LogDir           = 'C:\ProgramData\DeployLogs'
        LogFileName      = $null
        TextLogPath      = $null
        JsonLogPath      = $null
        EnableTranscript = $false
        TranscriptPath   = $null
        EnableEventLog   = $false
        EventLogName     = 'Deployment'
        EventSource      = 'AutoUnattend'
        CorrelationId    = $(New-Guid).Guid
        EnableDebug      = $false
        ConsoleInfo      = $false
    }

    # Resolve effective values: prefer provided options, otherwise use defaults
    $effective = @{}
    foreach ($k in $defaults.Keys) {
        if ($Options -and $Options.ContainsKey($k)) {
            $effective[$k] = $Options[$k]
        } else {
            $effective[$k] = $defaults[$k]
        }
    }

    
    # Generate timestamp (UTC) for log filenames used when filenames not explicitly provided
    $script:timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmssZ')

    # Finalize script-scope variables content
    $script:ScriptName = $ScriptName
    $script:LogDir = $effective['LogDir']
    $script:LogFileName = $effective['LogFileName']
    $script:TextLogPath = $effective['TextLogPath']
    $script:JsonLogPath = $effective['JsonLogPath']
    $script:EnableTranscript = [bool]$effective['EnableTranscript']
    $script:TranscriptPath = $effective['TranscriptPath']
    $script:EnableEventLog = [bool]$effective['EnableEventLog']
    $script:EventLogName = $effective['EventLogName']
    $script:EventSource = $effective['EventSource']
    $script:CorrelationId = $effective['CorrelationId']
    $script:EnableDebug = [bool]$effective['EnableDebug']
    $script:ConsoleInfo = [bool]$effective['ConsoleInfo']

    # Determine LogFileName if not provided
    if ([string]::IsNullOrWhiteSpace($script:LogFileName)) {
        $script:LogFileName = "$($script:ScriptName).$($script:timestamp)"
    }
    # Determine TextLogPath / JsonLogPath / TranscriptPath if not provided
    if ([string]::IsNullOrWhiteSpace($script:TextLogPath)) {
        $script:TextLogPath = Join-Path -Path $script:LogDir -ChildPath "$($script:LogFileName).log" 
    }
    if ([string]::IsNullOrWhiteSpace($script:JsonLogPath)) {
        $script:JsonLogPath = Join-Path -Path $script:LogDir -ChildPath "$($script:LogFileName).jsonl" 
    }
    if ($script:EnableTranscript -and [string]::IsNullOrWhiteSpace($script:TranscriptPath)) {
        $script:TranscriptPath = Join-Path -Path $script:LogDir -ChildPath "$($script:LogFileName).transcript.log" 
    }

    # Determine elevation for Event Log usage
    $script:principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $script:IsElevated = $script:principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Ensure that logs base directory exists
    if (-not (Test-Path $script:LogDir)) {
        try { 
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
        } catch {
            Write-Warning "Could not create log directory '$($script:LogDir)': $($_.Exception.Message)" 
        }
    }
        
    # Start transcript only if explicitly enabled
    if ($script:EnableTranscript -and (-not $script:TranscriptEnabled)) {  # avoid re-starting
        try {
            Start-Transcript -Path $script:TranscriptPath -IncludeInvocationHeader -ErrorAction Stop | Out-Null
            $Script:TranscriptEnabled = $true
        } catch {
            Write-Warning "Could not start transcript: $($_.Exception.Message)"
        }
    }

    # Initialize Event Log only if enabled AND elevated
    if( -not $script:EventLogReady ) {  # avoid re-initialization
        if ($script:EnableEventLog) {
            if ($script:IsElevated) {
                try {
                    $existingLogs = Get-EventLog -List | Select-Object -ExpandProperty Log
                    if ($existingLogs -notcontains $script:EventLogName) {
                        New-EventLog -LogName $script:EventLogName -Source $script:EventSource
                        Limit-EventLog -LogName $script:EventLogName -OverflowAction OverwriteAsNeeded -MaximumSize 32MB
                    } else {
                        $sourceExists = $false
                        try {
                            Get-EventLog -LogName $script:EventLogName -Source $script:EventSource -ErrorAction Stop | Out-Null
                            $sourceExists = $true
                        } catch {
                            $sourceExists = $false
                        }
                        if (-not $sourceExists) {
                            New-EventLog -LogName $script:EventLogName -Source $script:EventSource
                        }
                    }
                    $script:EventLogReady = $true
                } catch {
                    Write-Warning "Event Log initialization failed: $($_.Exception.Message)"
                    $script:EventLogReady = $false
                }
            } else {
                Write-Warning "Event Log is enabled but the session is not elevated. Event log will be skipped."
                $script:EventLogReady = $false
            }
        }
    }
    Write-Verbose "Logger initialized. TextLogPath='$($script:TextLogPath)', JsonLogPath='$($script:JsonLogPath)'"
}

# ---- Helpers ----

function ConvertTo-FlatHashtable {
    <#
    .SYNOPSIS
      Flattens nested hashtables/arrays into dotted-key dictionary for optional metadata.
    .OUTPUTS
      System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $InputObject,
        [string] $Prefix = ''
    )
    $flat = @{}
    foreach ($k in $InputObject.Keys) {
        $key = if ($Prefix) { "$Prefix.$k" } else { "$k" }
        $v = $InputObject[$k]
        if ($v -is [hashtable]) {
            (ConvertTo-FlatHashtable -InputObject $v -Prefix $key).GetEnumerator() | ForEach-Object {
                $flat[$_.Key] = $_.Value
            }
        } elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
            # Represent arrays as comma-separated for compactness
            $flat[$key] = ($v -join ',')
        } else {
            $flat[$key] = $v
        }
    }
    return $flat
}

function Write-TextLogLine {
    <#
    .SYNOPSIS
      Appends a single plain text line to the log file.
    .PARAMETER Level
      INFO | WARN | ERROR | DEBUG
    .PARAMETER Message
      Human-readable message.
    .PARAMETER Fields
      Optional hashtable of metadata; appended compactly to the end of the line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [string] $TimeStamp,

        [Parameter(Mandatory = $false)]
        [hashtable] $Fields
    )

    if ([string]::IsNullOrWhiteSpace($TimeStamp)) {
        # is empty / whitespace only / or not provided/null
        $TimeStamp = (Get-Date).ToUniversalTime().ToString('o')  # ISO 8601, UTC
    }

    $line = "[{0}] [{1}] {2}" -f $TimeStamp, $Level, $Message

    # Minimal metadata
    $meta = @{
        CorrelationId = $script:CorrelationId
        Script        = $script:ScriptName
        Host          = $env:COMPUTERNAME
        User          = $env:USERNAME
        Pid           = $PID
    }

    if ($Fields) {
        try {
            $flat = ConvertTo-FlatHashtable -InputObject $Fields
            foreach ($k in $flat.Keys) { $meta[$k] = $flat[$k] }
        } catch {
            $meta['Fields'] = ($Fields | Out-String).Trim()
        }
    }

    if ($meta.Count -gt 0) {
        $kv = $meta.GetEnumerator() | ForEach-Object {
            $k = $_.Key
            $v = if ($null -ne $_.Value) { "$($_.Value)".Replace("`r", " ").Replace("`n", " ") } else { '' }
            "$k=$v"
        }
        $line = "$line  " + ($kv -join ' ')
    }

    try {
        Add-Content -Path $script:TextLogPath -Value $line -Encoding UTF8
    } catch {
        Write-Warning "Failed writing text log '$($script:TextLogPath)': $($_.Exception.Message)"
    }
}

function Write-JsonLogLine {
    <#
    .SYNOPSIS
      Appends a single JSON object line to the JSONL log file.
    .PARAMETER Level
      INFO | WARN | ERROR | DEBUG
    .PARAMETER Message
      Human-readable message.
    .PARAMETER Fields
      Optional hashtable of metadata; merged into JSON object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [string] $TimeStamp,

        [Parameter(Mandatory = $false)]
        [hashtable] $Fields
    )

    if ([string]::IsNullOrWhiteSpace($TimeStamp)) {
        # is empty / whitespace only / or not provided/null
        $TimeStamp = (Get-Date).ToUniversalTime().ToString('o')  # ISO 8601, UTC
    }

    $entry = [ordered]@{
        Timestamp     = $TimeStamp
        Level         = $Level
        Message       = $Message
        CorrelationId = $script:CorrelationId
        Hostname      = $env:COMPUTERNAME
        Script        = $script:ScriptName
        User          = $env:USERNAME
        Pid           = $PID
    }

    if ($Fields) {
        try {
            $flatFields = ConvertTo-FlatHashtable -InputObject $Fields
            foreach ($k in $flatFields.Keys) { $entry[$k] = $flatFields[$k] }
        } catch {
            $entry['Fields'] = $Fields
        }
    }

    try {
        ($entry | ConvertTo-Json -Depth 8 -Compress) | Add-Content -Path $script:JsonLogPath -Encoding UTF8
    } catch {
        Write-Warning "Failed writing JSON log '$($script:JsonLogPath)': $($_.Exception.Message)"
    }
}

function Write-StructuredLog {
    <#
    .SYNOPSIS
      Core writer used by Trace-* helpers. Writes to text, JSON, console, and Event Log simultaneously.
    .PARAMETER Level
      Log level: INFO, WARN, ERROR, or DEBUG.
    .PARAMETER Message
      Human-readable description.
    .PARAMETER Fields
      Optional hashtable of contextual fields (flattened and included in both text and JSON output).
    .EXAMPLE
      Write-StructuredLog -Level INFO -Message "Process done" -Fields @{ Pid=$PID; Exit=0 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [hashtable] $Fields
    )
    if ($Level -eq 'DEBUG' -and -not $script:EnableDebug) {
        return  # skip debug messages if not enabled
    }
    $timeStamp = (Get-Date).ToUniversalTime().ToString('o')  # ISO 8601, UTC
    # Always write both formats: TEXT + JSON
    Write-TextLogLine -Level $Level -Message $Message -TimeStamp $timeStamp -Fields $Fields
    Write-JsonLogLine -Level $Level -Message $Message -TimeStamp $timeStamp -Fields $Fields

    # Console streams (optional, concise)
    switch ($Level) {
        'INFO' { if ($script:ConsoleInfo) { Write-Information "[INFO ] $Message"  -InformationAction Continue } }
        'WARN' { if ($script:ConsoleInfo) { Write-Information "[WARN ] $Message"  -InformationAction Continue } }
        'ERROR' { if ($script:ConsoleInfo) { Write-Information "[ERROR] $Message"  -InformationAction Continue } }
        'DEBUG' { if ($script:EnableDebug) { Write-Verbose "[DEBUG] $Message" } }
    }

    # Windows Event Log (concise; only if enabled and ready)
    if ($script:EnableEventLog -and $script:EventLogReady) {
        try {
            $eventId = switch ($Level) {
                'INFO' { 1000 }
                'WARN' { 1001 }
                'ERROR' { 1002 }
                'DEBUG' { 1003 }
            }
            $entryType = switch ($Level) {
                'INFO' { 'Information' }
                'WARN' { 'Warning' }
                'ERROR' { 'Error' }
                'DEBUG' { 'Information' } # avoid flooding warnings/errors
            }
            $msg = "$Message`nCorrelationId=$($script:CorrelationId)`nScript=$($script:ScriptName)`nHost=$($env:COMPUTERNAME)"
            Write-EventLog -LogName $script:EventLogName -Source $script:EventSource -EventId $eventId -EntryType $entryType -Message $msg -Category 0
        } catch {
            Write-Warning "Failed writing to Event Log: $($_.Exception.Message)"
        }
    }
}

# ===== Public API: Trace-* functions =====

function Trace-Log {
    <#
    .SYNOPSIS
      Write a structured log entry with specified level.
    .PARAMETER Level
      Log level: INFO, WARN, ERROR, or DEBUG.
    .PARAMETER Message
      Human-readable log message.
    .PARAMETER Fields
      Optional hashtable of contextual metadata to include in log entry.
    .EXAMPLE
      Trace-Log -Level INFO -Message "Operation completed" -Fields @{ Duration="2.5s" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string] $Level,
        [Parameter(Mandatory)]
        [string] $Message,
        [hashtable] $Fields
    )
    Write-StructuredLog -Level $Level -Message $Message -Fields $Fields
}

function Trace-Info {
    <#
    .SYNOPSIS
      Write an informational log entry.
    .PARAMETER Message
      Human-readable log message.
    .PARAMETER Fields
      Optional hashtable of contextual metadata.
    .EXAMPLE
      Trace-Info "Script started successfully"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Fields
    )
    Write-StructuredLog -Level 'INFO'  -Message $Message -Fields $Fields
}
function Trace-Warning {
    <#
    .SYNOPSIS
      Write a warning log entry.
    .PARAMETER Message
      Human-readable warning message.
    .PARAMETER Fields
      Optional hashtable of contextual metadata.
    .EXAMPLE
      Trace-Warning "Retrying failed operation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Fields
    )
    Write-StructuredLog -Level 'WARN'  -Message $Message -Fields $Fields 
}
function Trace-Error {
    <#
    .SYNOPSIS
      Write an error log entry.
    .PARAMETER Message
      Human-readable error message.
    .PARAMETER Fields
      Optional hashtable of contextual metadata.
    .EXAMPLE
      Trace-Error "Failed to process file: invalid format"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Fields
    )
    Write-StructuredLog -Level 'ERROR' -Message $Message -Fields $Fields
}
function Trace-Debug {
    <#
    .SYNOPSIS
      Write a debug log entry (visible only if EnableDebug is true).
    .PARAMETER Message
      Human-readable debug message.
    .PARAMETER Fields
      Optional hashtable of diagnostic metadata.
    .EXAMPLE
      Trace-Debug "Variable state: $($var.Count) items"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [hashtable]$Fields
    )
    Write-StructuredLog -Level 'DEBUG' -Message $Message -Fields $Fields
}

function Get-LogDir {
    <#
    .SYNOPSIS
      Returns the current log directory path configured for the logger.
    .OUTPUTS
      System.String - The path to the directory where log files are written.
    .EXAMPLE
      $logPath = Get-LogDir
      Write-Host "Logs are being written to: $logPath"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:LogDir
}


################# Module init Code ###############

# Call initializer once on import with provided options or defaults

Initialize-Logger -Options $ModuleInitParams

# Fail-fast defaults for deployments
$global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'


Trace-Info "Deployment logger initialized." @{
    CorrelationId  = $script:CorrelationId
    TextLogPath    = $script:TextLogPath
    JsonLogPath    = $script:JsonLogPath
    TranscriptOn   = $script:EnableTranscript
    TranscriptPath = if ($script:EnableTranscript) { $script:TranscriptPath } else { '' }
    EventLogOn     = [bool]$script:EnableEventLog
    EventLogReady  = [bool]$script:EventLogReady
    EventLog       = $script:EventLogName
    Source         = $script:EventSource
    
}

# Stop transcript on session exit only if enabled
if ($EnableTranscript) {
    $script:enableTranscriptAtEnd = $EnableTranscript
    Register-EngineEvent PowerShell.Exiting -Action {
        try {
            if ($script:enableTranscriptAtEnd) {
                Stop-Transcript | Out-Null
            }
        } catch {
            # Transcript may already be stopped or unavailable during shutdown; safe to ignore.
            return
        }
    } | Out-Null
}

# Export Initialize-Logger so callers can call it after Import-Module
Export-ModuleMember -Function Initialize-Logger
# Export Trace-* helpers and core writer so scripts can call them after Import-Module
Export-ModuleMember -Function Trace-Log, Trace-Info, Trace-Warning, Trace-Error, Trace-Debug, Get-LogDir
