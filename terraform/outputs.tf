output "server_ipv4" {
  description = "Public IPv4 (bootstrap only — day-to-day access is over Tailscale)."
  value       = hcloud_server.agent.ipv4_address
}

output "server_id" {
  description = "Hetzner server id."
  value       = hcloud_server.agent.id
}

output "firewall_id" {
  description = "Cloud firewall id."
  value       = hcloud_firewall.agent.id
}

output "tailscale_hint" {
  description = "After deploy, `tailscale ip -4` on the server. make ssh uses it."
  value       = "run: ssh ${var.admin_username}@$(terraform output -raw server_ipv4) 'tailscale ip -4'"
}
