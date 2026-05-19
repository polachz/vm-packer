
locals {

  file_templates = {
    for key, value in var.file_templates : key => templatefile(value.template, merge(value.vars, {
      vm_user_name = var.template_vmx_path == "" ? var.template_user_name : var.cloned_vm_username
      vm_user_password = var.template_vmx_path == "" ? var.template_user_password : var.cloned_vm_password
      windows_edition = var.windows_edition == "" ? value.vars.image_name : var.windows_edition
      windows_language = var.windows_language
      windows_input_language = var.windows_input_language
      static_ip      = var.clone_static_ip
      gateway        = var.clone_gateway
      dns            = var.clone_dns
      ssh_public_key = var.win_ssh_public_key
    }))
  }
  
  vmrun_path = "${var.vmware_workstation_path}/vmrun.exe"

  vmx_path = "${var.output_directory}/${var.cloned_vm_name}.vmx" 
}

# ====== Builder: vmware-vmx ======
source "vmware-vmx" "clone" {
  headless  = var.headless
  source_path    = var.template_vmx_path            # e.g. D:/VMs/Win11-GOLD/Win11.vmx
  vm_name        = var.cloned_vm_name

  communicator   = "ssh"
  # We are modifing template VM, so we use template user credentials - typically Administrator
  # Is not recommended to change this name for Windows builds
  # Template user is created by template builder
  # Clone VM User is created during this build,then template user is disabled  
  ssh_username   = var.template_user_name
  ssh_password   = var.template_user_password
  ssh_timeout    = var.ssh_timeout

  output_directory = var.output_directory

  vmx_data = {
    "displayName" = var.cloned_vm_name
  }

  # We provide shutdown by sysprep - set the shutdown command to empty string
  shutdown_command = ""

  skip_compaction = true
}

build {
  name    = "windows-clone"
  sources = ["source.vmware-vmx.clone"]
  
  # Upload unattend.xml template result to the VM
  # This file is recipe for final VM modifications
  # Create final VM user etc...
  provisioner "file" {
    content     = local.file_templates["/unattend.xml"]
    destination = "C:\\Windows\\System32\\Sysprep\\unattend.xml"
  }

  # Upload SSH public key for Administrators group (if provided)
  # administrators_authorized_keys is required for OpenSSH when user is in Administrators group.
  # ACL is set in the following powershell provisioner.
  dynamic "provisioner" {
    for_each = var.win_ssh_public_key != "" ? [1] : []
    labels   = ["file"]
    content {
      content     = var.win_ssh_public_key
      destination = "C:\\ProgramData\\ssh\\administrators_authorized_keys"
    }
  }

  # Fix ACL on administrators_authorized_keys (OpenSSH requires SYSTEM+Administrators only, no inheritance)
  dynamic "provisioner" {
    for_each = var.win_ssh_public_key != "" ? [1] : []
    labels   = ["powershell"]
    content {
      inline = [
        "$f = 'C:\\ProgramData\\ssh\\administrators_authorized_keys'",
        "icacls $f /inheritance:r /grant 'SYSTEM:(F)' /grant 'BUILTIN\\Administrators:(F)'",
        "Write-Host 'SSH public key installed and ACL set.'"
      ]
    }
  }

  # The Microsoft Edge is in some crazy state after template creation
  # and this cause cloning Vm failure. 
  # These steps fix this issue.
  provisioner "powershell" {
    inline = [
      "Write-Host 'Fixing Microsoft Edge Issues...'",
      "get-appxpackage -allusers -name \"Microsoft.MicrosoftEdge\" | Remove-appxpackage",
      "get-appxpackage -allusers -name \"Microsoft.MicrosoftEdge.Stable\" | Remove-appxpackage"
    ]
  }


# Run the Sysprep.exe in guest OS and then shutdown the VM
provisioner "powershell" {
  
  # If you have an administrator for elevation
  # – it is more reliable than -Verb RunAs
  # elevated_user     = var.win_admin_user      # must exist in guest and be in Administrators
  # elevated_password = var.win_admin_password  # corresponding password

  # Inline commands
  inline = [
    "Write-Host 'Going to run Sysprep...'",
    # Find the correct path to 64bit sysprep from 32bit / 64bit context
    "$path = \"$env:WINDIR\\Sysnative\\Sysprep\\sysprep.exe\"",
    "if (-not (Test-Path $path)) { $path = \"$env:WINDIR\\System32\\Sysprep\\sysprep.exe\" }",

    # Diagnostic: verify existence of the sysprep.exe
    "if (-not (Test-Path $path)) { throw \"sysprep.exe not found: $path\" }",

    # Run Sysprep – without interaction, wait for completion, then VM will be shutdown
    "Start-Process -FilePath $path -ArgumentList '/generalize /oobe /shutdown /quiet /mode:vm' -Wait",

    # (Optional) echo for log
    "Write-Host 'Sysprep done; guest is going down...'"
  ]
}

# To finalize VM template, we have to use workaround
# The VM is now powered off. But on the first power on 
# Sysprep steps must be provided, and it's time consuming, 
# plus VM modifying
# To get VM to final state, we have to power it on again 
# and wait for initialization steps to be finished.
# The unattend.xml file define step to create a file
# C:\ProgramData\DeployLogs\bootstrap.finished
# and this is a flag that the initialization is finished
# When the file is detected, we have VM final state and 
# we can finally shutdown the VM.


provisioner "shell-local" {
  # PowerShell -Command: read the inline temp file and execute it
  execute_command = [
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-Command",
    "[Console]::OutputEncoding=[Text.UTF8Encoding]::UTF8; $content = [System.IO.File]::ReadAllText('{{.Script}}'); Invoke-Expression $content"
  ]

  inline = [<<-PS
    #region Parameters
    $vmrun = "${local.vmrun_path}"
    $vmx   = "${local.vmx_path}"
    $gu    = "${var.cloned_vm_username}"
    $gp    = "${var.cloned_vm_password}"

    # Timeouts and polling
    $timeoutPowerOffMin  = 20   # wait for VM to power off
    $timeoutBootstrapMin = 45   # total time to wait for bootstrap.finished after power on
    $pollIntervalSec     = 10   # polling interval
    #endregion

    $ErrorActionPreference = 'Stop'

    # --- Helpers: path normalization & running state detection ---
    function Normalize-PathLike([string]$p) {
      if ([string]::IsNullOrWhiteSpace($p)) { return "" }
      $t = $p.Trim()
      if ($t -match '^file:/+') { $t = $t -replace '^file:/+', '' }  # strip file:/// prefix
      $t = $t -replace '/', '\\'                                     # unify slashes
      $t = $t.ToLowerInvariant()                                     # lowercase
      $t = $t.Trim('"')                                              # remove quotes
      return $t
    }

    function Get-RunningVmxList() {
      $listOutput = & $vmrun -T ws list 2>&1
      $lines = $listOutput | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
      if ($lines.Count -eq 0) { return @() }
      $entries = @()
      foreach ($line in $lines) {
        if ($line -match '^total running vms:') { continue }
        $entries += (Normalize-PathLike $line)
      }
      return $entries
    }

    function Is-OurVmxRunning([string]$ourVmx) {
      $normalizedOur = Normalize-PathLike $ourVmx
      $ourName = [System.IO.Path]::GetFileName($normalizedOur)

      $running = Get-RunningVmxList
      if ($running.Count -eq 0) { return $false }

      foreach ($entry in $running) {
        if ($entry -eq $normalizedOur) { return $true }              # full path match
        $entryName = [System.IO.Path]::GetFileName($entry)
        if ($entryName -eq $ourName) { return $true }                # filename-only match
      }

      # Additional fallback: if VMware Tools returns an IP, the VM is powered on
      try {
        $ipProc = Start-Process -FilePath $vmrun -ArgumentList @(
          "-T","ws","getGuestIPAddress", $ourVmx
        ) -NoNewWindow -Wait -PassThru
        if ($ipProc.ExitCode -eq 0) { return $true }
      } catch { }

      return $false
    }

    function Test-ProvisioningFile([string]$ourVmx, [string]$user, [string]$pass) {
      # Returns $true if C:\ProgramData\DeployLogs\bootstrap.finished exists
      $targetFile = "C:\\ProgramData\\DeployLogs\\bootstrap.finished"
      $p = Start-Process -FilePath $vmrun -ArgumentList @(
        "-T", "ws",
        "-gu", $user, "-gp", $pass,
        "fileExistsInGuest", $ourVmx, $targetFile
      ) -NoNewWindow -Wait -PassThru
      return ($p.ExitCode -eq 0)
    }

    Write-Host "Checking whether the VM is powered off..."

    #region Wait until VM is powered off (not present in 'vmrun -T ws list')
    $deadlineOff = (Get-Date).AddMinutes($timeoutPowerOffMin)
    while ($true) {
      $isRunning = Is-OurVmxRunning -ourVmx $vmx

      if (-not $isRunning) {
        Write-Host "VM is powered off (not listed among running VMs)."
        break
      }

      if ((Get-Date) -gt $deadlineOff) {
        Write-Error "Timeout: VM is still running; exceeded expected power-off time."
        exit 1
      }

      Start-Sleep -Seconds $pollIntervalSec
    }
    #endregion

    #region Power on VM
    Write-Host "Powering on the VM..."
    $startProc = Start-Process -FilePath $vmrun -ArgumentList @(
      "-T", "ws",
      "start", $vmx, "nogui"
    ) -NoNewWindow -Wait -PassThru

    if ($startProc.ExitCode -ne 0) {
      Write-Error "Failed to start the VM. Exit code: $($startProc.ExitCode)"
      exit 1
    }

    Start-Sleep -Seconds 10
    #endregion

    #region Wait for provisioning completion flag
    Write-Host "Waiting for provisioning completion (bootstrap.finished)..."
    $deadlineBootstrap = (Get-Date).AddMinutes($timeoutBootstrapMin)

    while ($true) {
      $ok = Test-ProvisioningFile -ourVmx $vmx -user $gu -pass $gp
      if ($ok) {
        Write-Host "Provisioning complete (bootstrap.finished found)."
        break
      }

      if ((Get-Date) -gt $deadlineBootstrap) {
        Write-Error "Timeout while waiting for bootstrap.finished."
        exit 1
      }

      Start-Sleep -Seconds $pollIntervalSec
    }
    #endregion

    #region Trigger guest shutdown via vmrun (runProgramInGuest)
    Write-Host "Triggering guest shutdown (10s timeout, forced)..."
    $guestExe  = "C:\\Windows\\System32\\cmd.exe"
    # Important: quote the 'Packer Shutdown' comment properly for cmd
    $guestArgs = "/c shutdown /s /t 10 /f /d p:4:1 /c ""Packer Shutdown"""

    $shutdownProc = Start-Process -FilePath $vmrun -ArgumentList @(
      "-T", "ws",
      "-gu", $gu, "-gp", $gp,
      "runProgramInGuest", $vmx,
      $guestExe, $guestArgs
    ) -NoNewWindow -Wait -PassThru

    if ($shutdownProc.ExitCode -ne 0) {
      Write-Error "Failed to invoke shutdown in the guest. vmrun exit code: $($shutdownProc.ExitCode)"
      exit 1
    }
    #endregion

    #region Final wait: ensure VM is powered off
    Write-Host "Waiting for the VM to power off after shutdown..."
    $deadlineFinalOff = (Get-Date).AddMinutes($timeoutPowerOffMin)

    while ($true) {
      $isRunning = Is-OurVmxRunning -ourVmx $vmx

      if (-not $isRunning) {
        Write-Host "VM has powered off successfully."
        break
      }

      if ((Get-Date) -gt $deadlineFinalOff) {
        Write-Error "Timeout: VM is still running after shutdown command."
        exit 1
      }

      Start-Sleep -Seconds $pollIntervalSec
    }
    #endregion
  PS
  ]
}


}

