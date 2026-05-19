variable "headless" {
  description = "Run VM without GUI window. Set to false on VMware Workstation 26 (26H1) and newer — headless mode has a known bug causing Sysprep to fail with SSH error 2300218 in Windows clone builds."
  type        = bool
  default     = false
}

variable "winrm_insecure" {
  description = "Skip validating the winrm ssl certificate."
  type        = bool
  default     = true
}

variable "winrm_use_ssl" {
  description = "Use winrm ssl connection."
  type        = bool
  default     = false
}

variable "ssh_timeout" {
  description = "SSH timeout"
  type        = string
  default     = "30m"
}

variable "windows_edition" {
  description = "Windows edition of the ISO file to install (this is usefull to overwrite for Windows 11 Pro or Server Core/Datacenter)."
  type        = string
  default     = ""
}

variable "windows_language" {
  description = "Windows language to use. The ISO file must contain this lanugage."
  type        = string
  default     = "en-US"
}

variable "windows_input_language" {
  description = "Windows language for the keyboard to use. The ISO file must contain this lanugage."
  type        = string
  default     = "en-US"
}

variable "provisioner" {
  description = "The packer provisioner commands."
  type        = list(string)
}

variable "template_vm_name" {
  description = "Name of the VM"
  type        = string
  default     = "packer-vm"
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "cpus" {
  description = "Number of CPUs"
  type        = number
  default     = 2
}

variable "disk_adapter_type" {
  description = "Disk adapter type"
  type        = string
  default     = "nvme"
}

variable "disk_size" {
  description = "Disk size in MB"
  type        = number
  default     = 40000
}

variable "cdrom_adapter_type" {
  description = "CDROM adapter type"
  type        = string
  default     = "sata"
}

variable "iso_url" {
  description = "URL to the ISO file"
  type        = string
  default     = ""
}

variable "iso_checksum" {
  description = "Checksum of the ISO file"
  type        = string
  default     = ""
}

variable "guest_os_type" {
  description = "Guest OS type for VMware"
  type        = string
  default     = "windows9_64Guest"
}

variable "network_adapter_type" {
  description = "Network adapter type"
  type        = string
  default     = "e1000e"
}

variable "boot_command" {
  description = "Boot command sequence"
  type        = list(string)
  default     = []
}

variable "boot_wait" {
  description = "Time to wait before sending boot command"
  type        = string
  default     = "10s"
}

variable "http_directory" {
  description = "Directory to serve over HTTP"
  type        = string
  default     = "http"
}

variable "tools_upload_flavor" {
  description = "VMware tools upload flavor"
  type        = string
  default     = ""
}

variable "tools_mode" {
  description = "VMware tools management mode (upload, attach, off)"
  type        = string
  default     = "upload"
}

variable "file_templates" {
  description = "Template files content configuration"
  type        = map(object({
    template = string
    vars     = map(string)
  }))
  default = {}
}

variable "additional_cd_files" {
  description = "Additional files attached to the virtual machine as iso."
  type        = list(string)
  default     = []
}

variable "template_user_name" {
  type        = string
  description = "Name of the user created on the template VM. Preserve 'Administrator' for windows templates. Change only if you really know what you are doing!!"
  default     = "Administrator"
}

variable "template_user_password" {
  type        = string
  sensitive   = true
  description = "Password for the user created on the template VM"
  default     = "packer"
}


variable "template_vmx_path" {
  type        = string
  description = "Path to a template VMX file. Clone will use this VMX file to create a new VM."
  default     = ""
}

variable "cloned_vm_name" {
  type        = string
  description = "Name of the new VM."
  default     = "windows-template-clone"
}

variable "cloned_vm_username" {
  type        = string
  description = "New local user created on the cloned VM."
  default     = "tester"
}

variable "cloned_vm_password" {
  type        = string
  sensitive   = true
  description = "Password for the new local user created on the cloned VM."
  default     = "test"
}

variable "output_directory" {
  type        = string
  description = "Output directory for the build."
}

variable "vmware_workstation_path" {
  type        = string
  description = "Local path to VMware Workstation binaries directory"
  default     = "C:/Program Files (x86)/VMware/VMware Workstation"
}

variable "win_ssh_public_key" {
  type        = string
  description = "SSH public key to install for the cloned Windows VM user (full string, e.g. 'ssh-ed25519 AAAA...'). Written to administrators_authorized_keys. Leave empty to skip."
  default     = ""
}

variable "clone_static_ip" {
  type        = string
  description = "Static IP address for the cloned VM in CIDR notation (e.g. '192.168.1.10/24'). Leave empty for DHCP."
  default     = ""
}

variable "clone_gateway" {
  type        = string
  description = "Default gateway for static IP configuration. Required if clone_static_ip is set."
  default     = ""
}

variable "clone_dns" {
  type        = string
  description = "DNS server for static IP configuration."
  default     = "8.8.8.8"
}
