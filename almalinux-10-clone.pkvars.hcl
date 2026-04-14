template_vmx_path = "artifacts/alma10-template/alma10-template.vmx"

cloned_vm_name     = "alma10-clone"
cloned_vm_username = "alma"
cloned_vm_password = "Password1!"

alma_clone_hostname             = "alma10-clone"
# Your SSH public key — paste the full string from ~/.ssh/id_ed25519.pub or similar
# Or use overriding mechanism - See README.md for details
# Leave empty ("") to skip SSH key injection (password-only access)
alma_ssh_public_key             = ""
alma_sudo_nopassword            = true

output_directory = "artifacts/alma10-clone"

# Required variable from variables.pkr.hcl (for Windows provisioner – not used here)
provisioner = []
