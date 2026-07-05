# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# Root Terraform configuration: providers, backend, and module wiring.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Remote state — S3 backend with DynamoDB state locking.
  # Bucket/table must be created once, out-of-band, before first `terraform init`.
  backend "s3" {
    bucket         = "datawave-terraform-state"          # pre-existing, versioned, SSE-KMS
    key            = "sql-federation/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "datawave-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "datawave-sql-federation"
      ManagedBy   = "terraform"
      Environment = var.environment
      Owner       = "Sunil Poricha - Cloud SRE - Technical Assessment 2026"
    }
  }
}

# EKS auth handled via exec plugin so this file works before/after cluster creation
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
