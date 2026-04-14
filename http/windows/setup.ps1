$ErrorActionPreference = "Stop"


# setup.ps1

function Invoke-CompanionScripts {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$ExcludePatterns = @(),

        [Parameter()]
        [string]$LogPath = "$env:SystemDrive\Windows\Temp\setup-companions.log"
    )

    try {
        # get path to this script (also works in PS 2.0/WinPE):
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
        $scriptDir  = Split-Path -Parent $scriptPath
        $scriptName = Split-Path -Leaf   $scriptPath

        Write-Host "===> Script: $scriptName"
        Write-Host "===> Folder: $scriptDir"
        Write-Host "===> Folder content list:"
        
        Get-ChildItem -LiteralPath $scriptDir | Format-Table -AutoSize | Out-String | Write-Host

        # Take all .ps1 except this script
        $toRun = Get-ChildItem -LiteralPath $scriptDir -Filter *.ps1 -File -ErrorAction Stop |
                Where-Object { $_.Name -ne $scriptName } |
                Sort-Object Name

        # Sort alphabetically
        $toRun = $toRun | Sort-Object Name

        if (-not $toRun -or $toRun.Count -eq 0) {
            Write-Host "===> Nothing to run. No more .ps1 scripts available"
            return
        }

        Write-Host "===> Going to run these scripts:"
        $toRun | ForEach-Object { Write-Host "    - $($_.Name)" }

        # Log file
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }

        foreach ($s in $toRun) {
            Write-Host "----> Executing: $($s.FullName)"
            Add-Content -Path $LogPath -Value ("[{0}] START {1}" -f (Get-Date), $s.FullName)

            try {
                # Executr the script in a new PowerShell process to avoid variable/function name conflicts

                Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$($s.FullName)`"" -Wait

                Add-Content -Path $LogPath -Value ("[{0}] OK    {1}" -f (Get-Date), $s.FullName)
            }
            catch {
                Write-Warning "Script error $($s.Name): $($_.Exception.Message)"
                Add-Content -Path $LogPath -Value ("[{0}] FAIL  {1} :: {2}" -f (Get-Date), $s.FullName, $_.Exception.Message)
                # Optionally re-throw the error to stop execution
                # throw
            }
        }
    }
    catch {
        Write-Error "Invoke-CompanionScripts failed: $($_.Exception.Message)"
        throw
    }
}


# Switch network connection to private mode
# Required for WinRM firewall rules
$profile = Get-NetConnectionProfile
Set-NetConnectionProfile -Name $profile.Name -NetworkCategory Private

# Enable WinRM service
winrm quickconfig -quiet
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Disable IPv6 because it leads to problems with proxmox terraform
Get-NetAdapter | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 }

# Reset auto logon count
# https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon-logoncount#logoncount-known-issue
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoLogonCount -Value 0

# Run a custom scripts if presents

Invoke-CompanionScripts -ExcludePatterns @("setup.ps1")

