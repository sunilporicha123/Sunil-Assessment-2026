# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# Security groups implementing least-privilege network access between
# EKS workloads and the pre-existing RDS instances.

resource "aws_security_group" "eks_to_rds" {
  name        = "${var.cluster_name}-eks-to-rds"
  description = "Allow EKS worker nodes to reach RDS sources on their DB ports only"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "PostgreSQL (DB1)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "MySQL (DB2)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS (S3, Secrets Manager, ECR, STS)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-eks-to-rds" }
}

# Ingress rules attached directly to the *existing* RDS security groups so that
# only traffic originating from EKS worker nodes is permitted — RDS remains
# otherwise closed. This assumes the RDS SG IDs are passed in via variables
# since the instances are pre-provisioned outside this stack.
resource "aws_security_group_rule" "rds_postgres_allow_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.rds_postgres_sg_id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Allow Trino pods on EKS to reach PostgreSQL RDS"
}

resource "aws_security_group_rule" "rds_mysql_allow_eks" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = var.rds_mysql_sg_id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Allow Trino pods on EKS to reach MySQL RDS"
}

# ALB Ingress security group — only 443 exposed publicly, 80 redirects to 443
resource "aws_security_group" "alb_ingress" {
  name        = "${var.cluster_name}-alb-ingress"
  description = "Public-facing ALB for Metabase dashboards and Trino UI"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-alb-ingress" }
}
