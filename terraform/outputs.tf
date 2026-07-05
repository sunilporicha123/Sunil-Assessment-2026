# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "datalake_bucket_name" {
  value = module.datalake_bucket.s3_bucket_id
}

output "audit_bucket_name" {
  value = module.audit_bucket.s3_bucket_id
}

output "trino_irsa_role_arn" {
  value = module.trino_irsa_role.iam_role_arn
}

output "rds_postgres_endpoint" {
  value = data.aws_db_instance.postgres_source.endpoint
}

output "rds_mysql_endpoint" {
  value = data.aws_db_instance.mysql_source.endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
