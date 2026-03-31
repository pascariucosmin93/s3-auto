resource "cloudflare_dns_record" "storage" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_storage
  type    = "A"
  content = var.lb_ip
  ttl     = 60
  proxied = false
}

resource "cloudflare_dns_record" "s3" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_s3
  type    = "A"
  content = var.lb_ip
  ttl     = 60
  proxied = false
}
