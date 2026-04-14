locals {
  # Extract plain IP from CIDR notation (e.g. "192.168.1.10/24" -> "192.168.1.10")
  # If clone_static_ip is empty, returns "" and Packer uses VMware guest IP detection
  ssh_host = var.clone_static_ip != "" ? split("/", var.clone_static_ip)[0] : ""

  user_data = templatefile("${path.root}/cloud-init/user-data.yml.pkrtpl", {
    username        = var.cloned_vm_username
    plain_password  = var.cloned_vm_password
    ssh_public_key  = var.alma_ssh_public_key
    sudo_nopassword = var.alma_sudo_nopassword
  })
  meta_data = templatefile("${path.root}/cloud-init/meta-data.yml.pkrtpl", {
    hostname   = var.alma_clone_hostname
    static_ip  = var.clone_static_ip
    gateway    = var.clone_gateway
    dns        = var.clone_dns
  })
  network_config = templatefile("${path.root}/cloud-init/network-config.yml.pkrtpl", {
    static_ip = var.clone_static_ip
    gateway   = var.clone_gateway
    dns       = var.clone_dns
  })
}

source "vmware-vmx" "alma-clone" {
  source_path      = var.template_vmx_path
  vm_name          = var.cloned_vm_name
  headless         = true
  output_directory = var.output_directory

  # Inject cloud-init data into VMX — VMware datasource reads them via open-vm-tools
  vmx_data = {
    "displayName"                        = var.cloned_vm_name
    "guestinfo.userdata"                 = base64encode(local.user_data)
    "guestinfo.userdata.encoding"        = "base64"
    "guestinfo.metadata"                 = base64encode(local.meta_data)
    "guestinfo.metadata.encoding"        = "base64"
    "guestinfo.network-config"           = base64encode(local.network_config)
    "guestinfo.network-config.encoding"  = "base64"
    "vmxstats.filename"                  = "${var.cloned_vm_name}.scoreboard"

    # Display: stretch guest to fit window
    "gui.enableStretchGuest"             = "TRUE"
  }

  communicator     = "ssh"
  ssh_username     = var.cloned_vm_username
  ssh_host         = local.ssh_host
  ssh_agent_auth   = true   # key from ssh-agent; no key file on disk needed
  ssh_timeout      = "5m"
  shutdown_command = "sudo poweroff"
}

build {
  name    = "almalinux-clone"
  sources = ["source.vmware-vmx.alma-clone"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "echo 'Cloud-init OK. VM is ready.'"
    ]
    valid_exit_codes = [0, 2]
  }

}
