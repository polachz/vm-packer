guest_os_type = "windows2022srvnext-64"
network_adapter_type = "e1000e"

file_templates = {
  "/unattend.xml" = {
    template = "./http/windows/unattend.xml.pkrtpl"
    vars = {
      image_name      = "Windows 11 Enterprise Evaluation"
    }
  }
}

template_vmx_path = "artifacts/win11-template/win11-template.vmx"

cloned_vm_username = "tester"
cloned_vm_password = "test"

boot_command   = []
provisioner    = []


cloned_vm_name   = "win11-clone"
output_directory = "artifacts/win11-clone"

# false = required on VMware Workstation 26 (26H1) — headless mode causes Sysprep failure
headless = false
