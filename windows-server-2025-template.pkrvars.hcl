guest_os_type = "windows2022srvnext-64"
network_adapter_type = "e1000e"

iso_url      = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
iso_checksum = "d0ef4502e350e3c6c53c15b1b3020d38a5ded011bf04998e950720ac8579b23d"


file_templates = {
  "/Autounattend.xml" = {
    template = "./http/windows/Autounattend-server.xml.pkrtpl"
    vars = {
      image_name      = "Windows Server 2025 SERVERSTANDARD"
    }
  }
}

additional_cd_files = [ 
  "./http/windows/setup.ps1",
  "./http/windows/setup-scripts/*",
]

os             = "win11"
ssh_username   = "Administrator"
communicator   = "ssh"
boot_command   = []
provisioner    = []

tools_upload_flavor = "windows"

template_vm_name = "srv2025-template" 
output_directory = "artifacts/srv2025-template"

headless = false
