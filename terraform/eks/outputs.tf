output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "Command to fetch cluster credentials once applied"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
