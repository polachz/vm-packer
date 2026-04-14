variable "alma_lock_root" {
  type        = bool
  description = "Lock the root account in the template (set to false to keep root accessible for debugging)"
  default     = true
}

variable "alma_ssh_public_key" {
  type        = string
  description = "SSH public key for the cloned VM user (full string, e.g. 'ssh-ed25519 AAAA...')"
  default     = ""
}

variable "alma_sudo_nopassword" {
  type        = bool
  description = "Grant the cloned VM user passwordless sudo"
  default     = false
}

variable "alma_clone_hostname" {
  type        = string
  description = "Hostname of the clone (used as cloud-init instance-id and local-hostname)"
  default     = "alma-clone"
}
