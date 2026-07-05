# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# Additional IAM: Jenkins CI/CD deploy role and the AWS Load Balancer Controller
# service account role. All roles follow least-privilege, resource-scoped policies.

data "aws_caller_identity" "current" {}

# --- Jenkins deploy role, assumed via OIDC from a CI runner or role-chaining ---
resource "aws_iam_role" "jenkins_deploy" {
  name = "${var.cluster_name}-jenkins-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/jenkins-agent-base-role"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "datawave-ci-cd"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "jenkins_deploy_policy" {
  name = "jenkins-eks-ecr-deploy"
  role = aws_iam_role.jenkins_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}

# --- AWS Load Balancer Controller IRSA role (for ALB Ingress) ---
module "alb_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                              = "${var.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- External Secrets Operator IRSA role: reads Secrets Manager into K8s Secrets ---
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["sql-federation:external-secrets"]
    }
  }
}

resource "aws_iam_role_policy" "external_secrets_read" {
  name = "external-secrets-read-only"
  role = module.external_secrets_irsa_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [
        var.secrets_manager_db_secret_arn_postgres,
        var.secrets_manager_db_secret_arn_mysql
      ]
    }]
  })
}
