source "vmware-iso" "alma-template" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  http_directory    = "http/almalinux"

  vm_name           = var.template_vm_name
  guest_os_type     = "centos8-64"
  version           = "19"

  cpus              = var.cpus
  memory            = var.memory
  disk_size         = var.disk_size
  disk_type_id      = "0"

  network_adapter_type = "vmxnet3"

  boot_command = [
    "<wait>",
    "<up>",
    "<wait1s>",
    "e",
    "<wait1s>",
    "<down><down>",
    "<wait1s>",
    "<leftCtrlOn>e<leftCtrlOff>",
    "<wait1s>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/almalinux-10-vmware.ks biosdevname=0 net.ifnames=0",
    "<wait1s>",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]
  boot_wait = "15s"

  ssh_username = var.template_user_name
  ssh_password = var.template_user_password
  ssh_timeout  = var.ssh_timeout

  shutdown_command     = "poweroff"  
  headless             = true
  vnc_bind_address     = "127.0.0.1"
  vnc_disable_password = true

  output_directory = var.output_directory
}

build {
  name    = "almalinux-template"
  sources = ["source.vmware-iso.alma-template"]

  provisioner "ansible" {
    playbook_file = "./ansible/vmware.yml"
    user          = "root"
    use_proxy     = false
    command       = "${abspath(path.root)}/ansible-wrapper.cmd"
    extra_arguments = [
      "-e", "ansible_python_interpreter=/usr/bin/python3",
      "-e", "ansible_ssh_pass=${var.template_user_password}",
      "-e", "lock_root=${var.alma_lock_root}"
    ]
  }
}
