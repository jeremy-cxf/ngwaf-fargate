// You can curl this url or use as a CNAME for your domain.
// Remember to account for any ingress policies.
output "load_balancer_dns" {
  value = aws_lb.alb.dns_name
}
