# Template builder for Windows 
# The Template is then used by clone process to deploy final VMs



source "vmware-iso" "template" {

  headless  = true
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  guest_os_type        = var.guest_os_type
  cpus                 = var.cpus
  memory               = var.memory
  disk_adapter_type    = var.disk_adapter_type
  disk_size            = var.disk_size
  network_adapter_type = var.network_adapter_type
  cdrom_adapter_type   = var.cdrom_adapter_type

  boot_command   = var.boot_command
  boot_wait      = var.boot_wait
  communicator   = "ssh"
  ssh_username   = var.template_user_name
  ssh_password   = var.template_user_password
  ssh_timeout    = var.ssh_timeout
  winrm_username = var.template_user_name
  winrm_password = var.template_user_password
  winrm_insecure = var.winrm_insecure
  winrm_use_ssl  = var.winrm_use_ssl

  cd_content = { "Autounattend.xml" = local.file_templates["/Autounattend.xml"] }
  cd_files = var.additional_cd_files
  cd_label = "UNATTEND"
  
  tools_mode          = var.tools_mode
  tools_upload_flavor = var.tools_upload_flavor

  output_directory = var.output_directory
  vm_name          = var.template_vm_name
  
  vmx_data = {
    "sata1.present" = "TRUE"
  } 

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""

}

build {
  name    = "windows-template"
  sources = ["source.vmware-iso.template"]

  

  provisioner "file" {
    source      = "./http/windows/setup-scripts/ps-logger.psm1"
    destination = "C:/Users/${var.template_user_name}/ps-logger.psm1"
  }
  
  provisioner "powershell" {
    elevated_user = var.template_user_name
    elevated_password = var.template_user_password
    script = "./http/windows/provisioner-scripts/install-vmware-tools.ps1"

  }

  #provisioner "windows-restart" {}
  
  provisioner "windows-restart" {
    # Planned reboot: /d p:4:1  -> planned (p), major=4 (Application), minor=1 (Maintenance)
      restart_command       = "shutdown /r /f /t 0 /d p:4:1 /c \"Packer planned reboot\""

    
    # (Optional) add a simple check that prints something once WinRM is up again
    restart_check_command = "powershell -command \"& { Write-Output 'VM restarted successfully.' }\""
  }


  # --- Disable Hibernation ---
  provisioner "powershell" {
    inline = [
      "Write-Host 'Disabling hibernation...'",
      "$ErrorActionPreference = 'Stop'",
      "powercfg -h off",
      "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power' -Name 'HibernateEnabled' -Value 0"
    ]
  }


  # Final VM cleaning -  > Eject Install ISO, remove Unattend ISO, etc
  post-processor "shell-local" {
    environment_vars = ["VMWARE_PATH=${var.vmware_workstation_path}"]
    command = "powershell -ExecutionPolicy Bypass -File ./local-scripts/cleanup-vmx.ps1 -VmxPath \"${var.output_directory}/${var.template_vm_name}.vmx\" "
  }
}
