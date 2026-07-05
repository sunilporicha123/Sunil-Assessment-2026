# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# VPC, subnets, NAT, and routing for the SQL Federation platform.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "prod" # cost control for non-prod
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS + ALB Ingress Controller auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                       = "1"
    "kubernetes.io/cluster/${var.cluster_name}"    = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.cluster_name}"    = "shared"
  }

  # Flow logs to S3 for network audit trail (security best practice)
  enable_flow_log                                 = true
  flow_log_destination_type                       = "s3"
  flow_log_destination_arn                        = module.audit_bucket.s3_bucket_arn
  flow_log_traffic_type                           = "ALL"
}
