# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# EKS cluster hosting Trino, Ranger, Elasticsearch, and Metabase workloads.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Security best practice: private API endpoint by default; public access
  # restricted to an explicit allow-list (e.g. office/VPN CIDRs) rather than 0.0.0.0/0.
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = length(var.allowed_admin_cidrs) > 0
  cluster_endpoint_public_access_cidrs = var.allowed_admin_cidrs

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_irsa = true # IAM Roles for Service Accounts - least-privilege pod IAM

  eks_managed_node_groups = {
    federation_workers = {
      instance_types = var.eks_node_instance_types
      min_size       = var.eks_node_min_size
      max_size       = var.eks_node_max_size
      desired_size   = var.eks_node_desired_size

      capacity_type = "ON_DEMAND"

      labels = {
        workload = "sql-federation"
      }

      # Nodes only get the minimal IAM permissions required by EKS itself;
      # workload-specific access (S3, Secrets Manager) is granted via IRSA below.
    }
  }

  # Encrypt Kubernetes secrets at rest with a dedicated KMS key
  cluster_encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = aws_kms_key.eks_secrets.arn
  }

  tags = {
    Terraform = "true"
  }
}

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets envelope encryption"
  deletion_window_in_days = 30
  enable_key_rotation      = true
}

# --- IRSA role: Trino pods -> S3 (data lake catalog) + Secrets Manager (DB creds) ---
module "trino_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-trino-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["sql-federation:trino"]
    }
  }
}

resource "aws_iam_role_policy" "trino_s3_access" {
  name = "trino-s3-datalake-readonly"
  role = module.trino_irsa_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          module.datalake_bucket.s3_bucket_arn,
          "${module.datalake_bucket.s3_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [
          var.secrets_manager_db_secret_arn_postgres,
          var.secrets_manager_db_secret_arn_mysql
        ]
      }
    ]
  })
}
