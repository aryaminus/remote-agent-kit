# Cloud firewall FIRST: the box never accepts a packet we didn't invite.
# After `make deploy` locks SSH to Tailscale, even port 22 is tailnet-only.
resource "hcloud_firewall" "agent" {
  name = "${var.server_name}-fw"

  # SSH from your IP only during bootstrap. Once Tailscale is up, Ansible
  # binds sshd to the tailnet IP and this rule can stay as break-glass.
  dynamic "rule" {
    for_each = var.my_ip != "" ? [var.my_ip] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = [rule.value]
    }
  }

  # ICMP so ping/uptime monitors work.
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # NOTE: no 80/443 rules — Telegram polls out, Tailscale needs no inbound
  # ports, and dashboards stay tailnet-only. Add them only if you run a
  # public reverse proxy (and read docs/privacy-considerations.md first).
}

resource "hcloud_ssh_key" "operator" {
  name       = "${var.server_name}-operator"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "agent" {
  name         = var.server_name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.operator.id]
  firewall_ids = [hcloud_firewall.agent.id]

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_username = var.admin_username
    ssh_public_key = var.ssh_public_key
  })

  labels = {
    managed-by = "remote-agent-kit"
    agent      = "hermes"
  }
}
