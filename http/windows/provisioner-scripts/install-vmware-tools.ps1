
# Path to the ISO uploaded by the Packer VMware plugin
# Default upload location is usually C:\Users\<username>\<flavor>.iso (e.g., windows.iso)

$loggerModuleName = 'ps-logger.psm1'
$panicFilePath = 'C:\ProgramData\DeployLogs-Panic.txt'
$scriptName = 'install-vmware-tools.ps1'
# ScriptName for logging purposes
$currentScriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

# Get the directory where the script is located
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
#build the full path to the logger module file
$loggerModulePath = Join-Path -Path $scriptDir -ChildPath $loggerModuleName

if (-not (Test-Path $loggerModulePath)) {
    $loggerModulePath = Join-Path -Path $env:USERPROFILE -ChildPath $loggerModuleName
    if (-not (Test-Path $loggerModulePath)) {
        Write-Error "Logger module not found in the script directory: $loggerModuleName"
        Set-Content -Force -Path $panicFilePath -Value "Logger module not found in the script directory: $loggerModuleName"
        throw
    }
}

try {
    # Import module with logger configuration (passed once at import time)
    Import-Module $loggerModulePath -Force -ArgumentList  $scriptName, @{
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

Write-Host "Installing VMware Tools..." -ForegroundColor Cyan

Trace-Info "Starting VMware Tools installation script."

$isoPath = Join-Path $env:USERPROFILE "windows.iso"

Trace-Info "Checking for VMware Tools ISO at: $isoPath"

# Check if the ISO file exists before attempting installation
if (Test-Path -Path $isoPath) {
    Trace-Info "ISO found. Beginning VMware Tools installation..."

    try {
        # Mount the ISO
        $mount = Mount-DiskImage -ImagePath $isoPath -PassThru

        # Retrieve the drive letter assigned to the mounted ISO
        $driveLetter = ($mount | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            Trace-Error "Could not determine the drive letter of the mounted ISO."
            throw
        }

        $drive = "$driveLetter`:"
        Trace-Info "ISO mounted as drive $drive"

        # Path to the VMware Tools installer inside the mounted ISO
        $installer = Join-Path $drive "setup.exe"
        $setup_arguments = '/S /v "/qn REBOOT=ReallySuppress"'
        $validExitCodes = @(0, 3010)
        # Confirm installer exists
        if (Test-Path $installer) {
            Trace-Info "Installer located: $installer"
            Trace-Info "Launching silent VMware Tools installation..."

            # Run silent installer
            $proc = Start-Process -FilePath $installer -ArgumentList $setup_arguments -Wait -PassThru
            Trace-Info "VMWare install process exited with code $($proc.ExitCode)."
            if ($validExitCodes -notcontains $proc.ExitCode) {
                Trace-Error "VMware Tools installation failed with exit code $($proc.ExitCode)."
                throw "Re-throwing to call cleanup..."
            }
            Write-Host "VMware Tools installation completed successfully." -ForegroundColor Green
            Trace-Info "VMware Tools installation completed successfully."
        } else {
            Trace-Error "VMware Tools installer was not found inside the ISO."
            throw 
        }

    } catch {
        Trace-Error "An error occurred during VMware Tools installation: $($_.Exception.Message)"
        exit 1
    } finally {
        # Attempt to dismount the ISO, even if installation fails
        if (Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue) {
            Trace-Info "Dismounting ISO..."
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
            exit 0
        }
    }
} else {
    Trace-Error "The VMware Tools ISO does not exist. Installation will be skipped."
    exit 1
}
