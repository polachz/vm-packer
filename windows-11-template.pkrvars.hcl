guest_os_type = "windows11-64"
network_adapter_type = "e1000e"

iso_url      = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
iso_checksum = "a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9"

file_templates = {
  "/Autounattend.xml" = {
    template = "./http/windows/Autounattend-win11.xml.pkrtpl"
    vars = {
      image_name      = "Windows 11 Enterprise Evaluation"
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

template_vm_name = "win11-template"
output_directory = "artifacts/win11-template"

headless = false
