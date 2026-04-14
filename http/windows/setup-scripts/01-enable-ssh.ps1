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

Trace-Info "Starting SSH enabling script."

# Force TLS 1.2 for GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Latest release tag redirect
$latestUrl = 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/'

# Use low-level WebRequest to read Location header without following redirect
$request = [System.Net.WebRequest]::Create($latestUrl)
$request.AllowAutoRedirect = $false
$response = $request.GetResponse()
$location = [string]$response.GetResponseHeader('Location')

if (-not $location) {
    throw "No 'Location' header found. Cannot detect latest release tag."
}

# Example of $location:
# https://github.com/PowerShell/Win32-OpenSSH/releases/tag/10.0.0.0p2-Preview

# Extract tag name (the part after /tag/)
$tag = ($location -split '/tag/')[1]
if (-not $tag) {
    Trace-Error "Unable to parse release tag from Location: $location"
    exit 1
}

# Build the /download/ URL base (keep the original tag including pX and -Preview)
$downloadBase = $location.Replace('/tag/', '/download/')  # ends with .../download/<tag>

# Derive the 'numeric' version used in MSI file names:
# Rules:
#  - keep only digits and dots
#  - drop anything after first non-digit/dot (e.g., 'p2-Preview')
# Examples:
#   '10.0.0.0p2-Preview' -> '10.0.0.0'
#   '9.8.3.0p2-Preview'  -> '9.8.3.0'
$numericVersion = ($tag -replace '[^0-9\.].*$', '')

if (-not $numericVersion) {
    Trace-Error "Unable to derive numeric version from tag: $tag"
    exit 1
}

# Compose the MSI file name for Win64
$msiFile = "OpenSSH-Win64-v$numericVersion.msi"

# Final MSI URL
$msiUrl = "$downloadBase/$msiFile"

Trace-Info "Latest OpenSSH Win64 MSI URL: $msiUrl"

try{

    $baseTemp   = [System.IO.Path]::GetTempPath()
    $unique     = [System.Guid]::NewGuid().ToString()
    $workDir    = [System.IO.Path]::Combine($baseTemp, "OpenSSH-Install-$unique")
    [System.IO.Directory]::CreateDirectory($workDir) | Out-Null
}
catch {
    Trace-Error "Failed to create temporary working directory: $($_.Exception.Message)"
    exit 1
}
if (-not (Test-Path $workDir)) {
    Trace-Error "Temporary working directory wasn't created: $workDir"
    exit 1
}

$msiFileName = Split-Path -Path $msiUrl -Leaf
$msiPath     = Join-Path -Path $workDir -ChildPath $msiFileName


try {
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
}
catch {
    Remove-Item -Path $workDir -Recurse -Force
    Trace-Error "Download failed: $($_.Exception.Message)"
    exit 1
}

if (-not (Test-Path $msiPath)) {
    Remove-Item -Path $workDir -Recurse -Force
    Trace-Error "MSI file was not downloaded to: $msiPath"
    exit 1
}

Trace-Info "MSI downloaded to: $msiPath"
# Install the MSI silently

$libLogDir = Get-LogDir   
$logPath = Join-Path $libLogDir "enable-ssh-OpenSSH-Install.log"

$msiArgs = @(
    "/i", "`"$msiPath`"",
    "ADDLOCAL=Server",
    "/qn",
    "/norestart",
    "/L*v", "`"$logPath`""
)

Trace-Info "Starting OpenSSH server Installation..."

$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Remove-Item -Path $workDir -Recurse -Force
    Trace-Error "msiexec failed with exit code $($proc.ExitCode). See log: $logPath"
    exit 1
}

Trace-Info "OpenSSH Server installed successfully."

# remove temp working directory
Remove-Item -Path $workDir -Recurse -Force


# Check 'sshd' service presence & status
$sshd = $null
try {
    Trace-Info "Checking 'sshd' service..."
    $sshd = Get-Service -Name 'sshd' -ErrorAction Stop
    Trace-Info ("'sshd' current status: " + $sshd.Status)
}
catch {
    Trace-Error "Failed to query 'sshd' service: $($_.Exception.Message)"
    exit 1
}

# Start 'sshd' if not running
try {
    if ($sshd.Status -eq 'Running') {
        Trace-Info "'sshd' is already running. Skipping start."
    }
    else {
        Trace-Info "Starting 'sshd' service..."
        Start-Service -Name 'sshd'
        Trace-Info "'sshd' started."
    }
}
catch {
    Trace-Error "Failed to start 'sshd': $($_.Exception.Message)"
    exit 1
}

# Ensure autostart (StartupType = Automatic)
try {
    Trace-Info "Setting 'sshd' StartupType = Automatic..."
    Set-Service -Name 'sshd' -StartupType Automatic
    Trace-Info "'sshd' StartupType set to Automatic."
}
catch {
    Trace-Error "Failed to set 'sshd' StartupType: $($_.Exception.Message)"
    exit 1
}

# Verify host keys & sshd_config generated under %ProgramData%\ssh
try {
    Trace-Info "Verifying host keys and sshd_config at %ProgramData%\\ssh..."
    $sshData = Join-Path $env:ProgramData 'ssh'
    if (-not (Test-Path $sshData)) {
        # The folder should be created on first service start
        Trace-Info "Waiting briefly for %ProgramData%\\ssh initialization..."
        Start-Sleep -Seconds 3
    }
    if (-not (Test-Path $sshData)) {
        throw "%ProgramData%\ssh not found. Ensure 'sshd' is running."
    }

    # Typical host key files (variations by version): ssh_host_ed25519_key, ssh_host_rsa_key, sshd_config
    $hostKeys = Get-ChildItem -Force $sshData -Filter 'ssh_host_*_key' -ErrorAction SilentlyContinue
    $config   = Join-Path $sshData 'sshd_config'

    if (($hostKeys -and $hostKeys.Count -gt 0) -and (Test-Path $config)) {
        Trace-Info "Host keys and sshd_config detected in %ProgramData%\\ssh."
    }
    else {
        throw "Host keys or sshd_config not found in %ProgramData%\ssh."
    }
}
catch {
    Trace-Error "Verification of keys/config failed: $($_.Exception.Message)"
    exit 1
}

# Firewall: allow TCP/22 for Private, Public, Domain profiles
try {
    Trace-Info "Configuring firewall rule for TCP/22..."
    $rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($rule) {
        Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile 'Private,Public,Domain' -Enabled True
        Trace-Info "Updated existing rule 'OpenSSH-Server-In-TCP' to profiles: Private,Public,Domain."
    }
    else {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
            -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
            -Profile 'Private,Public,Domain' | Out-Null
        Trace-Info "Created firewall rule 'OpenSSH-Server-In-TCP' for TCP/22 (Private,Public,Domain)."
    }
}
catch {
    Trace-Error "Firewall configuration failed: $($_.Exception.Message)"
    exit 1
}

# Final check: port 22 listening (optional but helpful)
try {
    Trace-Info "Checking if TCP/22 is listening..."
    $tcp22 = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
    if ($tcp22) {
        Trace-Info "TCP/22 is in LISTEN state (sshd active)."
    }
    else {
        Trace-Info "TCP/22 not detected as LISTEN. Check firewall/policies if needed."
    }
}
catch {
    Trace-Error "Port 22 listen check failed: $($_.Exception.Message)"
    # non-fatal
}

Trace-Info "OpenSSH Server setup completed."



