param(
    [Parameter(Mandatory = $true)]
    [string]$VmxPath
)

Write-Host "Running VMX cleanup on: $VmxPath" -ForegroundColor Cyan

if (-not (Test-Path $VmxPath)) {
    Write-Host "Error: VMX file not found at $VmxPath" -ForegroundColor Red
    exit 1
}

# Read VMX content
$lines = Get-Content -Path $VmxPath

# Filter variables
$newLines = New-Object System.Collections.Generic.List[string]

foreach ($line in $lines) {
    # 1. Remove sata1 controller and devices (The second CD-ROM usually used for scripts/unattend)
    if ($line -match "^sata1") {
        Write-Host "Removing line: $line" -ForegroundColor Gray
        continue
    }

    # 2. Eject content from sata0:0 (The OS ISO)
    # We replace the fileName with an empty value or auto detect, and ensure it's not connected at start
    if ($line -match "^sata0:0.fileName") {
        Write-Host "Clearing ISO from sata0:0" -ForegroundColor Gray
        $newLines.Add('sata0:0.fileName = "auto detect"')
        continue
    }
    
    # Also ensure startConnected is FALSE for sata0:0 if present, or add it if we want to force it?
    # Usually it's better to just set fileName to auto detect (physical drive) or empty.
    # If we want to strictly "eject" logic, 'auto detect' is closest to "empty drive" in VMWare Workstation often.
    
    $newLines.Add($line)
}

# Ensure sata0:0 is not connected at startup (optional, but good practice if empty)
# We can check if we need to add/modify `sata0:0.startConnected`.
# For simplicity, relying on fileName = "auto detect" acts like an empty tray if no physical disk is present, or uses physical. 
# Better: Set it to empty string? `sata0:0.fileName = ""` might cause issues. 
# "auto detect" is safer.

# Save back to file
$newLines | Set-Content -Path $VmxPath -Force
Write-Host "VMX cleanup complete." -ForegroundColor Green
