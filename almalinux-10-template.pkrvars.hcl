iso_url      = "https://repo.almalinux.org/almalinux/10.1/isos/x86_64/AlmaLinux-10.1-x86_64-boot.iso"
iso_checksum = "file:https://repo.almalinux.org/almalinux/10.1/isos/x86_64/CHECKSUM"

template_user_name     = "root"
template_user_password = "almalinux"
template_vm_name       = "alma10-template"

cpus      = 2
memory    = 2048
disk_size = 10240

output_directory = "artifacts/alma10-template"

# Set to false to keep root accessible for debugging
alma_lock_root = true

# Required variable from variables.pkr.hcl (for Windows provisioner – not used here)
provisioner = []
