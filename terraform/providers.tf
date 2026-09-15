# Hetzner Cloud provider. Token comes from HCLOUD_TOKEN env var
# (export it or put it in .env — never in a .tfvars file you commit).
provider "hcloud" {
  token = var.hcloud_token
}
