# Packer VM Build Project

This project automates the creation of Virtual Machines for VMware Workstation using [HashiCorp Packer](https://www.packer.io/). It supports building base templates and fast-cloning them into ready-to-use VM instances.

**Supported operating systems:**
- Windows 11
- Windows Server 2025
- AlmaLinux 10

## Prerequisites

- **VMware Workstation Pro** 17 or later
  > **VMware Workstation 26 (26H1) compatibility note:** Headless mode (`headless = true`) has a known bug in Windows clone builds — Sysprep fails with SSH error 2300218 when VNC is used. The variable `headless` defaults to `false` for Windows clone builds. If you are on an older version (25.x or earlier) and prefer headless operation, set `headless = true` in the respective `.pkvars.hcl` file.
- **Packer** in system PATH
- **PowerShell** for the menu script and Windows provisioner scripts
- **WSL** with Ansible installed — required for AlmaLinux builds only

## Workflow

All builds follow a two-stage process:

### Stage 1 — Template

Creates a "golden image" from an official ISO. The template is a clean, reusable VM that is never booted directly in production.

- **Windows**: Installs OS, VMware Tools, enables SSH/WinRM, runs baseline configuration scripts. *~15–30 min.*
- **AlmaLinux**: Installs OS via Kickstart, provisions with Ansible (open-vm-tools, cloud-init, cleanup). *~15–20 min.*

### Stage 2 — Clone

Clones the template into a ready-to-use VM instance.

- **Windows**: Clones the template, runs Sysprep to generalize the image, creates a local user. *~2–5 min.*
- **AlmaLinux**: Clones the template, injects cloud-init user-data and metadata via VMware guestinfo, waits for cloud-init to complete (user creation, SSH key, hostname, sudo). *~2–3 min.*

> You must build the **Template** at least once before creating a **Clone**.

## Usage

### Interactive Menu (Recommended)

```powershell
.\build-menu.ps1
```

If script execution is restricted:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-menu.ps1
```

The menu uses arrow keys for navigation. Hotkeys invoke the action directly without pressing Enter:

| Key | Action |
|-----|--------|
| `1` | Build Windows 11 Template |
| `2` | Clone Windows 11 |
| `3` | Build Windows Server 2025 Template |
| `4` | Clone Windows Server 2025 |
| `5` | Build AlmaLinux 10 Template |
| `6` | Clone AlmaLinux 10 |
| `d` | Open Deployment Profiles sub-menu |
| `x` | Exit |
| `Esc` / `Q` | Back / Exit |

For clone options (VM name, output directory, static IP) you are prompted interactively after selecting a clone action.

Use `-PackerLog` to enable verbose Packer logging:

```powershell
.\build-menu.ps1 -PackerLog
```

### Deployment Profiles

A deployment profile is a YAML file that describes a VM to clone — OS type, name, network settings, and OS-specific options. Profiles let you reproduce deployments without re-entering parameters each time.

#### Profile location

By default the menu looks for profiles in the `deployments/` folder inside the project. To keep profiles outside the repository set the `PACKER_DEPLOYMENTS_DIR` environment variable:

```powershell
# Per session
$env:PACKER_DEPLOYMENTS_DIR = "C:\MyVMConfigs"

# Permanently (current user)
[System.Environment]::SetEnvironmentVariable("PACKER_DEPLOYMENTS_DIR", "C:\MyVMConfigs", "User")
```

When the variable is set the menu footer shows the active path.

#### Profile format

```yaml
# Required: target OS
# Valid values: windows-11 | windows-server-2025 | almalinux-10
os: windows-server-2025

# Required: name for the cloned VM
vm_name: web-server-01

# Optional: output directory (default: artifacts/<vm_name>)
output_dir: D:\VMs\web-server-01

# Optional: static IP in CIDR notation. Omit or leave empty for DHCP.
static_ip: 192.168.1.10/24
gateway: 192.168.1.1
dns: 8.8.8.8

# Optional: clone VM credentials (overrides defaults from pkvars.hcl)
username: myuser
password: MyPassword1!

# Windows-specific (ignored for AlmaLinux):
win_ssh_public_key: "ssh-ed25519 AAAA..."

# AlmaLinux-specific (ignored for Windows):
hostname: web-server-01
ssh_public_key: "ssh-ed25519 AAAA..."
sudo_nopassword: true
```

Example profiles for all supported OSes are provided in the [`deployments/`](deployments/) directory: `alma-test.yml`, `win11-test.yml`, and `srv2025-test.yml`.

#### Running a profile from the menu

Select **Deployment Profiles...** (`d`) in the main menu. Each profile found in the profiles directory is listed and can be invoked by its hotkey or Enter.

#### Running a profile from the command line

```powershell
# By profile name (looks in PACKER_DEPLOYMENTS_DIR or .\deployments\)
.\build-menu.ps1 -Profile web-server-01

# By full path to any YAML file
.\build-menu.ps1 -DeploymentFile C:\MyVMConfigs\prod-db.yml
```

When `-Profile` or `-DeploymentFile` is provided the interactive menu is skipped and the build starts immediately.

### Command Line

#### Windows 11

```powershell
# Template
packer build -force -only="windows-template.vmware-iso.template" -var-file="windows-11-template.pkrvars.hcl" .

# Clone
packer build -force -only="windows-clone.vmware-vmx.clone" -var-file="windows-11-clone.pkvars.hcl" .
```

#### Windows Server 2025

```powershell
# Template
packer build -force -only="windows-template.vmware-iso.template" -var-file="windows-server-2025-template.pkrvars.hcl" .

# Clone
packer build -force -only="windows-clone.vmware-vmx.clone" -var-file="windows-server-2025-clone.pkvars.hcl" .
```

#### AlmaLinux 10

```powershell
# Template
packer build -force -only="almalinux-template.vmware-iso.alma-template" -var-file="almalinux-10-template.pkrvars.hcl" .

# Clone
packer build -force -only="almalinux-clone.vmware-vmx.alma-clone" -var-file="almalinux-10-clone.pkvars.hcl" .
```

## AlmaLinux — Architecture

### Build Pipeline

```
Packer (Windows) → VMware Workstation VM → Kickstart (unattended OS install)
    → SSH available → Ansible (via WSL)
        → vmware_guest: installs open-vm-tools
        → setup_cloud_init: installs cloud-init, deploys cloud.cfg
        → cleanup_vm: sanitizes template (logs, SSH host keys, machine-id, network profiles)
    → Template saved
    → Clone: VMX guestinfo injected with user-data + metadata
        → cloud-init runs on first boot: creates user, sets SSH key, configures hostname
```

### Windows–WSL Bridge

The AlmaLinux template build runs Ansible inside WSL because Ansible requires POSIX paths and SSH key permissions (`chmod 600`). The bridge:

1. `ansible-wrapper.cmd` — Windows batch entry point called by Packer
2. `ansible-wrapper.sh` — WSL bash script that converts Windows paths to WSL mount paths and invokes `ansible-playbook`

### cloud-init (Clone)

Clone configuration is injected via VMware guestinfo (`guestinfo.userdata` / `guestinfo.metadata`), base64-encoded. The VMware datasource in cloud-init reads these via open-vm-tools.

`cloud-init/user-data.yml.pkrtpl` supports:

| Variable | Description |
|----------|-------------|
| `cloned_vm_username` | Username to create |
| `cloned_vm_password` | Plain-text password |
| `alma_ssh_public_key` | SSH public key (optional) |
| `alma_sudo_nopassword` | Grant passwordless sudo (bool) |
| `alma_clone_hostname` | Hostname / cloud-init instance-id |

### Ansible Roles

| Role | Purpose |
|------|---------|
| `vmware_guest` | Installs and enables `open-vm-tools` / `vmtoolsd` |
| `setup_cloud_init` | Installs cloud-init, deploys `cloud.cfg` template, enables cloud-init services |
| `cleanup_vm` | Sanitizes the template: clears dnf cache, logs, SSH host keys, machine-id, network profiles |

`setup_cloud_init` deploys a known-good `cloud.cfg` from `ansible/roles/setup_cloud_init/templates/cloud.cfg.j2`, parameterized by:

| Variable | Default | Description |
|----------|---------|-------------|
| `cloud_init_user` | `almalinux` | Default user name in cloud.cfg |
| `disable_root` | `true` | Whether cloud-init locks the root account |

## Credentials

### Windows Template

| Field | Value |
|-------|-------|
| User | `Administrator` |
| Password | `packer` |

> Do not change template credentials — the clone build depends on them.

### Windows Clone

| Field | Default | Override |
|-------|---------|----------|
| User | `tester` | `username` in deployment profile, or `-var cloned_vm_username=...` |
| Password | `test` | `password` in deployment profile, or `-var cloned_vm_password=...` |

**SSH public key (optional):** keys are resolved through a fallback chain — see [SSH Key Resolution](#ssh-key-resolution) below. Set `win_ssh_public_key` to install a key for the clone user. Because the user is a member of the `Administrators` group, OpenSSH on Windows requires the key to be in `C:\ProgramData\ssh\administrators_authorized_keys` (not `~\.ssh\authorized_keys`) with ACL restricted to SYSTEM and Administrators only — the clone build handles this automatically.

### AlmaLinux Template

| Field | Value |
|-------|-------|
| User | `root` |
| Password | `almalinux` |

### AlmaLinux Clone

| Field | Default | Override |
|-------|---------|----------|
| User | `alma` | `username` in deployment profile, or `-var cloned_vm_username=...` |
| Password | `Password1!` | `password` in deployment profile, or `-var cloned_vm_password=...` |
| SSH key | *(none)* | `ssh_public_key` in deployment profile, or `.ssh_public_key` file — see [SSH Key Resolution](#ssh-key-resolution) |

## Variables Reference

Global defaults are defined in `variables.pkr.hcl` and `almalinux-variables.pkr.hcl`. Override them in your `.pkrvars.hcl` files.

### Common (Windows + AlmaLinux)

| Variable | Default | Description |
|----------|---------|-------------|
| `iso_url` | *(empty)* | URL to the ISO file |
| `iso_checksum` | *(empty)* | SHA256 checksum of the ISO |
| `output_directory` | *(required)* | Directory where the VM will be saved |
| `template_vm_name` | `"packer-vm"` | Name of the template VM |
| `cpus` | `2` | Number of virtual CPUs |
| `memory` | `4096` | RAM in MB |
| `disk_size` | `40000` | Disk size in MB |
| `ssh_timeout` | `"30m"` | SSH connection timeout |
| `template_vmx_path` | *(empty)* | Path to source VMX for clone builds |
| `cloned_vm_name` | `"windows-template-clone"` | Name of the cloned VM |
| `cloned_vm_username` | `"tester"` | User created on the clone (AlmaLinux pkvars override: `alma`) |
| `cloned_vm_password` | `"test"` | Password for the clone user (AlmaLinux pkvars override: `Password1!`) |
| `tools_upload_flavor` | `""` | VMware Tools flavor (`windows`) |
| `tools_mode` | `"upload"` | VMware Tools management mode |
| `clone_static_ip` | `""` | Static IP in CIDR notation (e.g. `192.168.1.10/24`). Empty = DHCP. |
| `clone_gateway` | `""` | Default gateway. Required when `clone_static_ip` is set. |
| `clone_dns` | `"8.8.8.8"` | DNS server for static IP configuration. |
| `win_ssh_public_key` | `""` | SSH public key for the Windows clone user. Written to `administrators_authorized_keys`. |

### AlmaLinux-specific

| Variable | Default | Description |
|----------|---------|-------------|
| `alma_lock_root` | `true` | Lock the root account in the template (set to `false` to keep root accessible for debugging) |
| `alma_ssh_public_key` | `""` | SSH public key for the clone user |
| `alma_sudo_nopassword` | `false` | Grant passwordless sudo |
| `alma_clone_hostname` | `"alma-clone"` | Hostname / cloud-init instance-id |

## SSH Key Resolution

SSH public keys are resolved automatically — you never need to paste a key into a menu prompt unless you want to override the default. The lookup order is:

1. **Explicit value** in the deployment YAML (`ssh_public_key` / `win_ssh_public_key`) or typed into the interactive prompt
2. **`.ssh_public_key` file** in the same directory as the deployment YAML (useful for per-config-folder keys)
3. **`.ssh_public_key` file** in the project root (`s:\packer\.ssh_public_key`)
4. **No key** — a warning is printed and the clone is built without SSH key authentication

The `.ssh_public_key` file is a plain text file containing a single public key line, e.g.:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@host
```

Both `.ssh_public_key` locations are listed in `.gitignore` so private key material is never accidentally committed.

**Windows note:** because the clone user is a member of `Administrators`, OpenSSH requires the key in `C:\ProgramData\ssh\administrators_authorized_keys` with restricted ACL — the build handles this automatically.

## Notes

- **Windows builds use SSH**, not WinRM, as the primary communicator due to WinRM performance issues with file transfers. WinRM remains available for post-build provisioning.
- **AlmaLinux SSH host keys** are deleted during template cleanup and regenerated by cloud-init (`ssh` module in `cloud_init_modules`) on first boot of the clone.
- **Display stretch mode** is enabled by default on AlmaLinux clones (`gui.enableStretchGuest = TRUE` in VMX).
- `PACKER_LOG=1` is set automatically by `build-menu.ps1 -PackerLog`.
