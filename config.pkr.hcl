packer {
  required_plugins {
    vmware = {
      version = "~> 1"
      source = "github.com/hashicorp/vmware"
    }
   # Windows Updates Community Provisioner
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = ">= 0.17.1"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}
