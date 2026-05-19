param(
    [switch]$PackerLog,
    [string]$Profile = "",          # Name of a deployment profile (without .yml extension)
    [string]$DeploymentFile = ""    # Full path to a deployment YAML file
)

# Set working directory to the script's location to ensure relative paths work
if ($PSScriptRoot) {
    Set-Location $PSScriptRoot
}

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

# 1. Check Packer
if (-not (Get-Command "packer" -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Packer is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Packer and add it to your PATH."
    exit 1
}
Write-Host " [OK] Packer is installed." -ForegroundColor Green

# 2. Check VMware Workstation
$Global:VmwarePath = ""

# Candidate paths to check (in priority order)
$vmwareCandidates = @(
    "C:\Program Files (x86)\VMware\VMware Workstation",
    "C:\Program Files\VMware\VMware Workstation"
)

# Registry lookup (most reliable — reflects actual install location)
$regKey = "HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation"
if (Test-Path $regKey) {
    $regPath = (Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue).InstallPath
    if (-not [string]::IsNullOrWhiteSpace($regPath)) {
        $regPath = $regPath.TrimEnd('\')
        if ($vmwareCandidates -notcontains $regPath) {
            $vmwareCandidates = @($regPath) + $vmwareCandidates
        } else {
            $vmwareCandidates = @($regPath) + ($vmwareCandidates | Where-Object { $_ -ne $regPath })
        }
    }
}

foreach ($candidate in $vmwareCandidates) {
    if (Test-Path (Join-Path $candidate "vmware.exe")) {
        $Global:VmwarePath = $candidate
        Write-Host " [OK] VMware Workstation found at: $candidate" -ForegroundColor Green
        break
    }
}

if ([string]::IsNullOrWhiteSpace($Global:VmwarePath)) {
    # Last resort: vmrun.exe in PATH
    if (Get-Command "vmrun" -ErrorAction SilentlyContinue) {
        $cmd = Get-Command "vmrun"
        $Global:VmwarePath = Split-Path $cmd.Source -Parent
        Write-Host " [OK] VMware Workstation found in PATH: $($Global:VmwarePath)" -ForegroundColor Green
    } else {
        Write-Host "Error: VMware Workstation not found." -ForegroundColor Red
        Write-Host "Please install VMware Workstation: https://www.vmware.com/products/workstation-pro.html"
        exit 1
    }
}
Write-Host "Prerequisites successfully checked." -ForegroundColor Green

# ============================================================
# Arrow-key menu engine
# ============================================================

# Each item: @{ Label = "..."; Separator = $false; Hotkey = "1"; Action = { scriptblock } }
# Separator items (Separator = $true) are non-selectable section dividers.
# Hotkey is an optional single character (string). Case-insensitive.
# Pressing the hotkey moves the cursor to that item; Enter confirms.
function Show-ArrowMenu {
    param(
        [string]$Title,
        [object[]]$Items,
        [string]$Footer = "",
        [switch]$ReturnSelection   # If set, returns selected item hashtable instead of invoking Action
    )

    # Build lookup: hotkey char (lowercase) -> index in $selectable
    $selectable  = @()   # indices into $Items of non-separator entries
    $hotkeyMap   = @{}   # char -> index in $selectable

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if (-not $Items[$i].Separator) {
            $si = $selectable.Count
            $selectable += $i
            $hk = $Items[$i].Hotkey
            if ($hk -and $hk.Length -eq 1) {
                $hotkeyMap[$hk.ToLower()] = $si
            }
        }
    }

    $cursor = 0   # index into $selectable

    # Compute hotkey column width for aligned rendering
    $hasHotkeys = $hotkeyMap.Count -gt 0

    [Console]::CursorVisible = $false

    try {
        while ($true) {
            # --- Render ---
            [Console]::Clear()

            Write-Host ""
            Write-Host "  $Title" -ForegroundColor Cyan
            Write-Host "  $('=' * ($Title.Length + 2))"
            Write-Host ""

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]

                if ($item.Separator) {
                    if ($item.Label -ne "") {
                        Write-Host "  -- $($item.Label) --" -ForegroundColor DarkGray
                    } else {
                        Write-Host ""
                    }
                    continue
                }

                $isSelected = ($selectable[$cursor] -eq $i)
                $hk = $item.Hotkey

                # Prefix: "> " for selected, "  " otherwise
                if ($isSelected) {
                    Write-Host "  > " -NoNewline -ForegroundColor Green
                } else {
                    Write-Host "    " -NoNewline
                }

                # Hotkey badge
                if ($hasHotkeys) {
                    if ($hk -and $hk.Length -eq 1) {
                        Write-Host "[" -NoNewline -ForegroundColor DarkGray
                        if ($isSelected) {
                            Write-Host $hk -NoNewline -ForegroundColor Yellow
                        } else {
                            Write-Host $hk -NoNewline -ForegroundColor DarkYellow
                        }
                        Write-Host "] " -NoNewline -ForegroundColor DarkGray
                    } else {
                        Write-Host "    " -NoNewline   # 4 chars to match "[X] "
                    }
                }

                # Label
                if ($isSelected) {
                    Write-Host $item.Label -ForegroundColor White
                } else {
                    Write-Host $item.Label -ForegroundColor Gray
                }
            }

            if ($Footer -ne "") {
                Write-Host ""
                Write-Host "  $Footer" -ForegroundColor DarkGray
            }

            Write-Host ""
            if ($hasHotkeys) {
                Write-Host "  [Up/Down] Move   [Enter] Select   [Key] Invoke directly   [Esc/Q] Back" -ForegroundColor DarkGray
            } else {
                Write-Host "  [Up/Down] Move   [Enter] Select   [Esc/Q] Back" -ForegroundColor DarkGray
            }

            # --- Input ---
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                "UpArrow" {
                    if ($cursor -gt 0) { $cursor-- }
                }
                "DownArrow" {
                    if ($cursor -lt ($selectable.Count - 1)) { $cursor++ }
                }
                "Enter" {
                    [Console]::CursorVisible = $true
                    [Console]::Clear()
                    $selectedItem = $Items[$selectable[$cursor]]
                    if ($ReturnSelection) {
                        return $selectedItem
                    }
                    if ($selectedItem.Action) {
                        & $selectedItem.Action
                    }
                    if ($script:MenuExit -or $script:MenuBack) {
                        $script:MenuBack = $false
                        return
                    }
                    [Console]::CursorVisible = $false
                }
                { $_ -eq "Escape" -or ($key.KeyChar -eq 'q') -or ($key.KeyChar -eq 'Q') } {
                    [Console]::CursorVisible = $true
                    return
                }
                default {
                    # Hotkey: jump cursor to matching item AND invoke immediately
                    $ch = $key.KeyChar.ToString().ToLower()
                    if ($ch -and $hotkeyMap.ContainsKey($ch)) {
                        $cursor = $hotkeyMap[$ch]
                        [Console]::CursorVisible = $true
                        [Console]::Clear()
                        $selectedItem = $Items[$selectable[$cursor]]
                        if ($ReturnSelection) {
                            return $selectedItem
                        }
                        if ($selectedItem.Action) {
                            & $selectedItem.Action
                        }
                        if ($script:MenuExit -or $script:MenuBack) {
                            $script:MenuBack = $false
                            return
                        }
                        [Console]::CursorVisible = $false
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# ============================================================
# YAML / Deployment config support
# ============================================================

function Get-DeploymentsDir {
    $dir = $env:PACKER_DEPLOYMENTS_DIR
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = Join-Path $PSScriptRoot "deployments"
    }
    return $dir
}

# Simple line-by-line YAML parser for flat key: value files (no nested structures).
function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    foreach ($line in (Get-Content $Path)) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        if ($line -match '^\s*([^#:]+?)\s*:\s*(.*?)\s*$') {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()
            if ($val -match '^(.*?)\s+#.*$') { $val = $matches[1].Trim() }
            $val = $val.Trim('"').Trim("'")
            $result[$key] = $val
        }
    }
    return $result
}

# Resolve SSH public key using fallback chain:
#   1. Value explicitly set in deployment YAML (ssh_public_key / win_ssh_public_key)
#   2. .ssh_public_key file in the same folder as the deployment YAML
#   3. .ssh_public_key file in the project root (PSScriptRoot)
#   4. Empty string + warning
function Resolve-SshPublicKey {
    param(
        [string]$ExplicitKey,       # Value from YAML or interactive input
        [string]$DeploymentDir = "" # Directory of the deployment file (for fallback #2)
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitKey)) {
        return $ExplicitKey
    }

    # Fallback 2: .ssh_public_key next to the deployment file
    if (-not [string]::IsNullOrWhiteSpace($DeploymentDir)) {
        $candidate = Join-Path $DeploymentDir ".ssh_public_key"
        if (Test-Path $candidate) {
            $key = (Get-Content $candidate -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($key)) {
                Write-Host "  [SSH] Key loaded from: $candidate" -ForegroundColor DarkGray
                return $key
            }
        }
    }

    # Fallback 3: .ssh_public_key in project root
    $rootCandidate = Join-Path $PSScriptRoot ".ssh_public_key"
    if (Test-Path $rootCandidate) {
        $key = (Get-Content $rootCandidate -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            Write-Host "  [SSH] Key loaded from: $rootCandidate" -ForegroundColor DarkGray
            return $key
        }
    }

    Write-Host "  [SSH] Warning: no SSH public key found — key will not be deployed." -ForegroundColor Yellow
    return ""
}

function Resolve-DeploymentFilePath {
    param([string]$ProfileName, [string]$FilePath)
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) { return $FilePath }
    $dir = Get-DeploymentsDir
    return Join-Path $dir "$ProfileName.yml"
}

function Resolve-OsConfig {
    param([string]$OsKey)
    switch ($OsKey.ToLower()) {
        "windows-11"          { return @{ Name="Windows 11 Clone";          VarFile="windows-11-clone.pkvars.hcl";          OnlyParam="windows-clone.vmware-vmx.clone";        IsClone=$true } }
        "windows-server-2025" { return @{ Name="Windows Server 2025 Clone"; VarFile="windows-server-2025-clone.pkvars.hcl"; OnlyParam="windows-clone.vmware-vmx.clone";        IsClone=$true } }
        "almalinux-10"        { return @{ Name="AlmaLinux 10 Clone";        VarFile="almalinux-10-clone.pkvars.hcl";        OnlyParam="almalinux-clone.vmware-vmx.alma-clone"; IsClone=$true } }
        default {
            Write-Host "Error: Unknown OS type '$OsKey'. Valid values: windows-11, windows-server-2025, almalinux-10" -ForegroundColor Red
            return $null
        }
    }
}

function Get-DeploymentProfiles {
    $dir = Get-DeploymentsDir
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem -Path $dir -Filter "*.yml" | Select-Object -ExpandProperty Name | ForEach-Object { $_ -replace '\.yml$', '' })
}

# ============================================================
# Helper: read a variable from an HCL var file
# ============================================================
function Get-PackerVariable {
    param([string]$VarFile, [string]$VarName)
    if (-not (Test-Path $VarFile)) { return $null }
    $content = Get-Content -Path $VarFile -Raw
    if ($content -match "$VarName\s*=\s*`"([^`"]+)`"") { return $matches[1] }
    return $null
}

# ============================================================
# Core build function
# ============================================================
function Run-PackerBuild {
    param(
        [string]$Name,
        [string]$VarFile,
        [string]$PackerOnlyParam,
        [bool]$IsClone = $false,
        [string]$VmName = "",
        [string]$OutputDir = "",
        [string]$StaticIp = "",
        [string]$Gateway = "",
        [string]$Dns = "",
        [string]$Hostname = "",
        [string]$SshPublicKey = "",       # AlmaLinux: alma_ssh_public_key
        [string]$WinSshPublicKey = "",    # Windows: win_ssh_public_key
        [string]$SudoNopassword = "",
        [string]$Username = "",           # Override cloned_vm_username
        [string]$Password = ""            # Override cloned_vm_password
    )

    Write-Host "`nPreparing to build: $Name" -ForegroundColor Cyan

    if (-not (Test-Path $VarFile)) {
        Write-Host "Error: Variable file '$VarFile' not found!" -ForegroundColor Red
        return
    }

    $defaultVmName = Get-PackerVariable -VarFile $VarFile -VarName "cloned_vm_name"
    $defaultOutDir = Get-PackerVariable -VarFile $VarFile -VarName "output_directory"

    if ([string]::IsNullOrWhiteSpace($VmName)) { $VmName = $defaultVmName }
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        if (-not [string]::IsNullOrWhiteSpace($VmName) -and $VmName -ne $defaultVmName) {
            $OutputDir = "artifacts/$VmName"
        } else {
            $OutputDir = $defaultOutDir
        }
    }

    # Check Output Directory
    if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        if (Test-Path $OutputDir) {
            Write-Host "Warning: Output directory '$OutputDir' already exists." -ForegroundColor Yellow
            $choice = Read-Host "Do you want to DELETE existing files and continue? (y/n)"
            if ($choice -eq 'y') {
                try {
                    Remove-Item -Path $OutputDir -Recurse -Force -ErrorAction Stop
                    Write-Host "Directory deleted." -ForegroundColor Green
                } catch {
                    Write-Host "Error deleting directory: $_" -ForegroundColor Red
                    return
                }
            } else {
                Write-Host "Build cancelled by user." -ForegroundColor Gray
                return
            }
        }
    } else {
        Write-Host "Warning: Could not determine output_directory. Proceeding without check." -ForegroundColor Yellow
    }

    # If Clone: Check Source VMX
    if ($IsClone) {
        $sourceVmx = Get-PackerVariable -VarFile $VarFile -VarName "template_vmx_path"
        if (-not [string]::IsNullOrWhiteSpace($sourceVmx)) {
            if (-not (Test-Path $sourceVmx)) {
                Write-Host "Error: Source VMX template not found at '$sourceVmx'" -ForegroundColor Red

                $sourceBuildName = ""; $sourceVarFile = ""
                $sourceOnlyParam = "windows-template.vmware-iso.template"

                if ($VarFile -match "windows-11") {
                    $sourceBuildName = "Windows 11 Template"
                    $sourceVarFile = "windows-11-template.pkrvars.hcl"
                } elseif ($VarFile -match "windows-server-2025") {
                    $sourceBuildName = "Windows Server 2025 Template"
                    $sourceVarFile = "windows-server-2025-template.pkrvars.hcl"
                } elseif ($VarFile -match "almalinux") {
                    $sourceBuildName = "AlmaLinux 10 Template"
                    $sourceVarFile = "almalinux-10-template.pkrvars.hcl"
                    $sourceOnlyParam = "almalinux-template.vmware-iso.alma-template"
                }

                if ($sourceBuildName) {
                    $createChoice = Read-Host "Build missing source template '$sourceBuildName' now? (y/n)"
                    if ($createChoice -eq 'y') {
                        Run-PackerBuild -Name $sourceBuildName -VarFile $sourceVarFile -PackerOnlyParam $sourceOnlyParam -IsClone $false
                        if (Test-Path $sourceVmx) {
                            Write-Host "Source template created. Proceeding with clone..." -ForegroundColor Green
                        } else {
                            Write-Host "Source template build seemed to fail. Aborting clone." -ForegroundColor Red
                            return
                        }
                    } else {
                        Write-Host "Clone aborted. Missing source." -ForegroundColor Gray
                        return
                    }
                } else {
                    Write-Host "Cannot determine source build configuration automatically. Aborting." -ForegroundColor Red
                    return
                }
            } else {
                Write-Host " [OK] Source template found: $sourceVmx" -ForegroundColor Green
            }
        } else {
            Write-Host "Warning: Could not determine template_vmx_path from var file. Clone might fail." -ForegroundColor Yellow
        }
    }

    Write-Host "Launching Packer..." -ForegroundColor Cyan
    if ($PackerLog) {
        Write-Host "Working directory: $PWD" -ForegroundColor Gray
        Write-Host "Packer build command: packer build -force -only=$PackerOnlyParam -var-file=$VarFile ..." -ForegroundColor Gray
        $env:PACKER_LOG = 1
        Write-Host "Enabled PACKER_LOG=1" -ForegroundColor DarkGray
    }

    # Ensure all required plugins are installed before building
    Write-Host "Running packer init..." -ForegroundColor DarkGray
    $initOutput = & packer init . 2>&1
    $initExitCode = $LASTEXITCODE
    $initOutput | ForEach-Object { Write-Host $_ }
    $initHasError = $initOutput | Select-String -Pattern "^Error:" -Quiet
    if ($initExitCode -ne 0 -or $initHasError) {
        Write-Host "" 
        Write-Host "Error: packer init failed — one or more plugins could not be installed." -ForegroundColor Red
        Write-Host "Check internet connectivity or install missing plugins manually:" -ForegroundColor Yellow
        Write-Host "  packer init ." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Press any key to return to the menu..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        return
    }
    if ($IsClone) {
        Write-Host ""
        Write-Host "Please ignore the 'shutdown_command was not specified' warning." -ForegroundColor Yellow
        Write-Host "This is normal for clones." -ForegroundColor Yellow
        Write-Host ""
    }

    $extraVars = @()
    if (-not [string]::IsNullOrWhiteSpace($VmName))       { $extraVars += @("-var", "cloned_vm_name=$VmName") }
    if (-not [string]::IsNullOrWhiteSpace($OutputDir))    { $extraVars += @("-var", "output_directory=$OutputDir") }
    if (-not [string]::IsNullOrWhiteSpace($StaticIp)) {
        $extraVars += @("-var", "clone_static_ip=$StaticIp")
        $extraVars += @("-var", "clone_gateway=$Gateway")
        $extraVars += @("-var", "clone_dns=$Dns")
    }
    if (-not [string]::IsNullOrWhiteSpace($Hostname))      { $extraVars += @("-var", "alma_clone_hostname=$Hostname") }
    if (-not [string]::IsNullOrWhiteSpace($SshPublicKey))    { $extraVars += @("-var", "alma_ssh_public_key=$SshPublicKey") }
    if (-not [string]::IsNullOrWhiteSpace($WinSshPublicKey)) { $extraVars += @("-var", "win_ssh_public_key=$WinSshPublicKey") }
    if (-not [string]::IsNullOrWhiteSpace($SudoNopassword)) { $extraVars += @("-var", "alma_sudo_nopassword=$SudoNopassword") }
    if (-not [string]::IsNullOrWhiteSpace($Username))      { $extraVars += @("-var", "cloned_vm_username=$Username") }
    if (-not [string]::IsNullOrWhiteSpace($Password))      { $extraVars += @("-var", "cloned_vm_password=$Password") }

    $startTime = Get-Date
    & packer build -force -on-error=abort -only="$PackerOnlyParam" -var-file="$VarFile" -var "vmware_workstation_path=$Global:VmwarePath" @extraVars .

    Write-Host ""
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Packer build completed successfully." -ForegroundColor Green
    } else {
        Write-Host "Packer build failed with exit code $LASTEXITCODE." -ForegroundColor Red
    }
    Write-Host ""
    if ($PackerLog) { Remove-Item Env:\PACKER_LOG -ErrorAction SilentlyContinue }

    $endTime  = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    $totalMinutes = ($duration.Hours * 60) + $duration.Minutes
    Write-Host "Build duration: $totalMinutes min $($duration.Seconds) sec." -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Press any key to return to the menu..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

# ============================================================
# Interactive: ask for clone customization parameters
# ============================================================
function Read-CloneParameters {
    param(
        [string]$DefaultVmName,
        [bool]$IsAlmaLinux  = $false,
        [bool]$ForWindows   = $false
    )

    Write-Host ""
    Write-Host "--- Clone Customization ---" -ForegroundColor Cyan
    Write-Host "Press Enter to accept the default shown in [brackets]."
    Write-Host ""

    $vmName = Read-Host "VM name [$DefaultVmName]"
    if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = $DefaultVmName }

    $defaultOut = "artifacts/$vmName"
    $outputDir = Read-Host "Output directory [$defaultOut]"
    if ([string]::IsNullOrWhiteSpace($outputDir)) { $outputDir = $defaultOut }

    $staticIp = Read-Host "Static IP in CIDR notation (e.g. 192.168.1.10/24) [Enter = DHCP]"
    $gateway = ""; $dns = ""
    if (-not [string]::IsNullOrWhiteSpace($staticIp)) {
        $gateway = Read-Host "Default gateway"
        $dns = Read-Host "DNS server [8.8.8.8]"
        if ([string]::IsNullOrWhiteSpace($dns)) { $dns = "8.8.8.8" }
    }

    $defaultUser = if ($IsAlmaLinux) { "alma" } else { "tester" }
    $defaultPass = if ($IsAlmaLinux) { "Password1!" } else { "test" }
    $username = Read-Host "Username [$defaultUser]"
    if ([string]::IsNullOrWhiteSpace($username)) { $username = "" }  # empty = use pkvars default
    $password = Read-Host "Password [$defaultPass]"
    if ([string]::IsNullOrWhiteSpace($password)) { $password = "" }  # empty = use pkvars default

    $result = @{ VmName = $vmName; OutputDir = $outputDir; StaticIp = $staticIp; Gateway = $gateway; Dns = $dns; SshPublicKey = ""; Username = $username; Password = $password }

    if ($ForWindows) {
        $sshKey = Read-Host "SSH public key override [Enter = use .ssh_public_key file or skip]"
        $result["SshPublicKey"] = $sshKey.Trim()
    }

    if ($IsAlmaLinux) {
        $hostname = Read-Host "Hostname [$vmName]"
        if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = $vmName }
        $result["Hostname"] = $hostname
        $sshKey = Read-Host "SSH public key override [Enter = use .ssh_public_key file or skip]"
        $result["SshPublicKey"] = $sshKey.Trim()
    }

    return $result
}

# ============================================================
# Deployment profile: run a build from a YAML config file
# ============================================================
function Run-DeploymentProfile {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        Write-Host "Error: Deployment file not found: '$FilePath'" -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        return
    }

    Write-Host "Loading deployment config: $FilePath" -ForegroundColor Cyan
    $cfg = Read-SimpleYaml -Path $FilePath

    $osKey = $cfg["os"]
    if ([string]::IsNullOrWhiteSpace($osKey)) {
        Write-Host "Error: 'os' field is required in deployment config." -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        return
    }

    $osCfg = Resolve-OsConfig -OsKey $osKey
    if ($null -eq $osCfg) {
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        [Console]::ReadKey($true) | Out-Null
        return
    }

    $vmName       = if ($cfg.ContainsKey("vm_name"))    { $cfg["vm_name"] }    else { "" }
    $outputDir    = if ($cfg.ContainsKey("output_dir")) { $cfg["output_dir"] } else { "" }
    $staticIp     = if ($cfg.ContainsKey("static_ip"))  { $cfg["static_ip"] }  else { "" }
    $gateway      = if ($cfg.ContainsKey("gateway"))    { $cfg["gateway"] }    else { "" }
    $dns          = if ($cfg.ContainsKey("dns"))         { $cfg["dns"] }        else { "" }
    $hostname     = if ($cfg.ContainsKey("hostname"))   { $cfg["hostname"] }   else { "" }
    $sudoNoPwd    = if ($cfg.ContainsKey("sudo_nopassword")) { $cfg["sudo_nopassword"] } else { "" }
    $username     = if ($cfg.ContainsKey("username"))       { $cfg["username"] }       else { "" }
    $password     = if ($cfg.ContainsKey("password"))       { $cfg["password"] }       else { "" }

    $deploymentDir = Split-Path $FilePath -Parent

    # Resolve SSH keys through fallback chain (YAML → deployment folder → repo root → warning)
    $sshKey    = Resolve-SshPublicKey -ExplicitKey $cfg["ssh_public_key"]     -DeploymentDir $deploymentDir
    $winSshKey = Resolve-SshPublicKey -ExplicitKey $cfg["win_ssh_public_key"] -DeploymentDir $deploymentDir

    Write-Host ""
    Write-Host "Deployment summary:" -ForegroundColor Cyan
    Write-Host "  OS:         $osKey"
    Write-Host "  VM name:    $vmName"
    Write-Host "  Output dir: $(if ($outputDir) { $outputDir } else { "artifacts/$vmName (auto)" })"
    Write-Host "  IP:         $(if ($staticIp) { $staticIp } else { 'DHCP' })"
    if ($staticIp) {
        Write-Host "  Gateway:    $gateway"
        Write-Host "  DNS:        $(if ($dns) { $dns } else { '8.8.8.8' })"
    }
    Write-Host "  Username:   $(if ($username) { $username } else { '(default from pkvars)' })"
    Write-Host "  Password:   $(if ($password) { '***' } else { '(default from pkvars)' })"
    Write-Host ""

    Run-PackerBuild `
        -Name $osCfg.Name -VarFile $osCfg.VarFile -PackerOnlyParam $osCfg.OnlyParam -IsClone $osCfg.IsClone `
        -VmName $vmName -OutputDir $outputDir -StaticIp $staticIp -Gateway $gateway `
        -Dns $(if ($dns) { $dns } else { "8.8.8.8" }) `
        -Hostname $hostname -SshPublicKey $sshKey -WinSshPublicKey $winSshKey -SudoNopassword $sudoNoPwd `
        -Username $username -Password $password
}

# ============================================================
# CLI mode: -Profile or -DeploymentFile bypasses the menu
# ============================================================
if (-not [string]::IsNullOrWhiteSpace($Profile) -or -not [string]::IsNullOrWhiteSpace($DeploymentFile)) {
    $resolvedPath = Resolve-DeploymentFilePath -ProfileName $Profile -FilePath $DeploymentFile
    Run-DeploymentProfile -FilePath $resolvedPath
    exit 0
}

# ============================================================
# Deployment Profiles sub-menu
# ============================================================
function Show-DeploymentSubMenu {
    $deploymentsDir = Get-DeploymentsDir
    $footer = if ($env:PACKER_DEPLOYMENTS_DIR) {
        "Profiles dir: $deploymentsDir  (PACKER_DEPLOYMENTS_DIR)"
    } else {
        "Profiles dir: $deploymentsDir  (set PACKER_DEPLOYMENTS_DIR to use a different location)"
    }

    # Auto-assign hotkeys a-z (skip q=quit, x=exit)
    $hotkeyChars = 'a','b','c','d','e','f','g','h','i','j','k','l','m',
                   'n','o','p','r','s','t','u','v','w','y','z'

    while ($true) {
        $profiles = Get-DeploymentProfiles

        $items = @()
        if ($profiles.Count -eq 0) {
            $items += @{ Label = "(no profiles found)"; Separator = $false; DeployPath = "" }
        } else {
            $hkIdx = 0
            foreach ($p in $profiles) {
                $hk = if ($hkIdx -lt $hotkeyChars.Count) { $hotkeyChars[$hkIdx++] } else { "" }
                $items += @{
                    Label      = $p
                    Separator  = $false
                    Hotkey     = $hk
                    DeployPath = (Join-Path $deploymentsDir "$p.yml")
                }
            }
        }

        $items += @{ Label = ""; Separator = $true }
        $items += @{ Label = "[ Back ]  (or Esc)"; Separator = $false; Hotkey = ""; DeployPath = "" }

        # Use ReturnSelection — no closures, no scope issues
        $selected = Show-ArrowMenu -Title "Deployment Profiles" -Items $items -Footer $footer -ReturnSelection

        # null = Esc/Q pressed → exit sub-menu
        if ($null -eq $selected) { break }

        # Back item has empty DeployPath
        if ([string]::IsNullOrWhiteSpace($selected.DeployPath)) { break }

        # Run the chosen profile
        Run-DeploymentProfile -FilePath $selected.DeployPath

        # After build, loop back to redraw the sub-menu (unless exiting entirely)
        if ($script:MenuExit) { break }
    }
}

# ============================================================
# Main interactive menu
# ============================================================
$script:MenuExit = $false
$script:MenuBack = $false

function Show-MainMenu {
    $items = @(
        @{ Label = "Windows 11";                                  Separator = $true  }
        @{ Label = "Build Windows 11 Template";                   Separator = $false; Hotkey = "1"
           Action = { Run-PackerBuild -Name "Windows 11 Template" -VarFile "windows-11-template.pkrvars.hcl" -PackerOnlyParam "windows-template.vmware-iso.template" } }
        @{ Label = "Clone Windows 11  (from Template)";           Separator = $false; Hotkey = "2"
           Action = {
               $defaultName = Get-PackerVariable -VarFile "windows-11-clone.pkvars.hcl" -VarName "cloned_vm_name"
               $p = Read-CloneParameters -DefaultVmName $defaultName -ForWindows $true
               $resolvedKey = Resolve-SshPublicKey -ExplicitKey $p.SshPublicKey
               Run-PackerBuild -Name "Windows 11 Clone" -VarFile "windows-11-clone.pkvars.hcl" -PackerOnlyParam "windows-clone.vmware-vmx.clone" -IsClone $true `
                   -VmName $p.VmName -OutputDir $p.OutputDir -StaticIp $p.StaticIp -Gateway $p.Gateway -Dns $p.Dns -WinSshPublicKey $resolvedKey `
                   -Username $p.Username -Password $p.Password
           } }

        @{ Label = "Windows Server 2025";                         Separator = $true  }
        @{ Label = "Build Windows Server 2025 Template";          Separator = $false; Hotkey = "3"
           Action = { Run-PackerBuild -Name "Windows Server 2025 Template" -VarFile "windows-server-2025-template.pkrvars.hcl" -PackerOnlyParam "windows-template.vmware-iso.template" } }
        @{ Label = "Clone Windows Server 2025  (from Template)";  Separator = $false; Hotkey = "4"
           Action = {
               $defaultName = Get-PackerVariable -VarFile "windows-server-2025-clone.pkvars.hcl" -VarName "cloned_vm_name"
               $p = Read-CloneParameters -DefaultVmName $defaultName -ForWindows $true
               $resolvedKey = Resolve-SshPublicKey -ExplicitKey $p.SshPublicKey
               Run-PackerBuild -Name "Windows Server 2025 Clone" -VarFile "windows-server-2025-clone.pkvars.hcl" -PackerOnlyParam "windows-clone.vmware-vmx.clone" -IsClone $true `
                   -VmName $p.VmName -OutputDir $p.OutputDir -StaticIp $p.StaticIp -Gateway $p.Gateway -Dns $p.Dns -WinSshPublicKey $resolvedKey `
                   -Username $p.Username -Password $p.Password
           } }

        @{ Label = "AlmaLinux 10";                                Separator = $true  }
        @{ Label = "Build AlmaLinux 10 Template";                 Separator = $false; Hotkey = "5"
           Action = { Run-PackerBuild -Name "AlmaLinux 10 Template" -VarFile "almalinux-10-template.pkrvars.hcl" -PackerOnlyParam "almalinux-template.vmware-iso.alma-template" } }
        @{ Label = "Clone AlmaLinux 10  (from Template)";         Separator = $false; Hotkey = "6"
           Action = {
               $defaultName = Get-PackerVariable -VarFile "almalinux-10-clone.pkvars.hcl" -VarName "cloned_vm_name"
               $p = Read-CloneParameters -DefaultVmName $defaultName -IsAlmaLinux $true
               $resolvedKey = Resolve-SshPublicKey -ExplicitKey $p.SshPublicKey
               Run-PackerBuild -Name "AlmaLinux 10 Clone" -VarFile "almalinux-10-clone.pkvars.hcl" -PackerOnlyParam "almalinux-clone.vmware-vmx.alma-clone" -IsClone $true `
                   -VmName $p.VmName -OutputDir $p.OutputDir -StaticIp $p.StaticIp -Gateway $p.Gateway -Dns $p.Dns -Hostname $p.Hostname -SshPublicKey $resolvedKey `
                   -Username $p.Username -Password $p.Password
           } }

        @{ Label = "";                                            Separator = $true  }
        @{ Label = "Deployment Profiles...";                      Separator = $false; Hotkey = "d"
           Action = { Show-DeploymentSubMenu } }

        @{ Label = "";                                            Separator = $true  }
        @{ Label = "Exit";                                        Separator = $false; Hotkey = "x"
           Action = { $script:MenuExit = $true } }
    )

    Show-ArrowMenu -Title "Packer Build Menu" -Items $items
}

Show-MainMenu
Write-Host "Goodbye." -ForegroundColor Cyan
