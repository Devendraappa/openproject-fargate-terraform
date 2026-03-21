output "alb_dns_name" {
  value = aws_lb.openproject.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.openproject.endpoint
}

output "secrets_manager_arn" {
  value = aws_secretsmanager_secret.openproject.arn
}

output "provisioned_vpc_id" {
  value = local.vpc_id
}
