variable "hcloud_token" {
  description = "Hetzner Cloud API token (read+write). Prefer HCLOUD_TOKEN env var."
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Hetzner server name."
  type        = string
  default     = "hermes"
}

# CPX21 = 3 vCPU / 4 GB / 80 GB, AMD x86. x86 is deliberate: the Hermes
# gateway crash-loops on ARM/aarch64 under systemd (upstream issue), and the
# ~6.6 GB install (browser engine + node + python) wants 80 GB headroom.
# Cheaper fallback: cx22 (2 vCPU / 4 GB / 40 GB). See docs/costs.md.
variable "server_type" {
  description = "Hetzner server type. Keep x86 (cpx/cx lines), not ARM (cax)."
  type        = string
  default     = "cpx21"
}

variable "image" {
  description = "Base image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "location" {
  description = "Hetzner location (fsn1, nbg1, hel1, ash, hil)."
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "Your SSH public key (contents, starting with ssh-ed25519/ssh-rsa)."
  type        = string
}

variable "admin_username" {
  description = "Non-root operator user created by cloud-init."
  type        = string
  default     = "hermes"
}

variable "my_ip" {
  description = "Your public IP/CIDR allowed to reach SSH before Tailscale takes over. Empty = SSH closed at edge (use Hetzner console for first boot)."
  type        = string
  default     = ""
}
