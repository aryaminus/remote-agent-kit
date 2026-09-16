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

# Verified 2026-09-16 via Hetzner API (fsn1, gross): cpx21 is listed but
# UNORDERABLE in fsn1 ("can no longer be ordered"); the x1 shared line is
# being retired region by region. cx33 (4 vCPU / 8 GB / 80 GB, ~€9.99) is the
# current headroom default; cx23 (~€6.49, 2/4/40) is the cheapest viable x86.
# Keep x86 (cpx/cx lines), never ARM (cax) — the Hermes gateway crash-loops
# on ARM/aarch64 under systemd.
variable "server_type" {
  description = "Hetzner server type. Keep x86 (cpx/cx lines), not ARM (cax)."
  type        = string
  default     = "cx33"
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
