# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "datawave-federation-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "CIDR block for the federation VPC"
  type        = string
  default     = "10.40.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread the cluster across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "eks_node_instance_types" {
  description = "Instance types for the EKS managed node group"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 3
}

variable "eks_node_min_size" {
  type    = number
  default = 2
}

variable "eks_node_max_size" {
  type    = number
  default = 6
}

# --- Existing RDS instances (assumed already provisioned per assignment) ---
variable "rds_postgres_endpoint" {
  description = "Endpoint (host:port) of the existing PostgreSQL RDS instance (DB1)"
  type        = string
}

variable "rds_postgres_sg_id" {
  description = "Security Group ID attached to the PostgreSQL RDS instance"
  type        = string
}

variable "rds_mysql_endpoint" {
  description = "Endpoint (host:port) of the existing MySQL RDS instance (DB2)"
  type        = string
}

variable "rds_mysql_sg_id" {
  description = "Security Group ID attached to the MySQL RDS instance"
  type        = string
}

variable "secrets_manager_db_secret_arn_postgres" {
  description = "ARN of the Secrets Manager secret holding PostgreSQL credentials"
  type        = string
}

variable "secrets_manager_db_secret_arn_mysql" {
  description = "ARN of the Secrets Manager secret holding MySQL credentials"
  type        = string
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks permitted to reach the EKS public API endpoint and bastion"
  type        = list(string)
  default     = []
}
