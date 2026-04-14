
$loggerModuleName = 'ps-logger.psm1'
$panicFilePath = 'C:\ProgramData\DeployLogs-Panic.txt'
# ScriptName for logging purposes
$currentScriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

# Get the directory where the script is located
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
#build the full path to the logger module file
$loggerModulePath = Join-Path -Path $scriptDir -ChildPath $loggerModuleName

if (-not (Test-Path $loggerModulePath)) {
    Write-Error "Logger module not found in the script directory: $loggerModuleName"
    Set-Content -Force -Path $panicFilePath -Value "Logger module not found in the script directory: $loggerModuleName"
    throw
}

try {
    # Import module with logger configuration (passed once at import time)
    Import-Module $loggerModulePath -Force -ArgumentList  $currentScriptName, @{
        LogDir       = 'C:\ProgramData\DeployLogs'
        EventLogName = 'Deployment'
        EventSource  = 'AutoUnattend'
        EnableDebug  = $true
    }
} catch {
    Write-Error "Failed to load logger file '$LoggerPath': $($_.Exception.Message)"
    Set-Content -Force -Path $panicFilePath -Value "Failed to load logger file '$LoggerPath': $($_.Exception.Message)"
    throw
}


Trace-Info "Starting CA certificate installation script."

# Build the full path to root-ca.cer
$certPath = Join-Path $scriptDir 'root-ca.cer'

# Check if the certificate file exists
if (-not (Test-Path $certPath)) {
    Trace-Info "The file 'root-ca.cer' was not found in the script directory. No certificate to install."
    exit 0
}

Trace-Info "Installing CA certificate from path: $certPath"

try {
    # Import the certificate into the Trusted Root Certification Authorities store
    Import-Certificate -FilePath $certPath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
    Trace-Info "Certificate successfully installed."
} catch {
    Trace-Error "Certificate installation failed: $($_.Exception.Message)"
    exit 1
}
Trace-Info "CA certificate installation script completed."

