# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
# S3 buckets: data lake source (DB3 in the diagram) and audit/log archive.

module "datalake_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.1"

  bucket = "datawave-federation-datalake-${var.environment}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_data.arn
      }
      bucket_key_enabled = true
    }
  }

  lifecycle_rule = [
    {
      id      = "transition-old-data"
      enabled = true
      transition = [
        { days = 90, storage_class = "STANDARD_IA" },
        { days = 365, storage_class = "GLACIER" }
      ]
    }
  ]
}

module "audit_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.1"

  bucket = "datawave-federation-audit-logs-${var.environment}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3_data.arn
      }
      bucket_key_enabled = true
    }
  }

  # Elasticsearch/OpenSearch snapshots and VPC flow logs land here for
  # long-term, tamper-evident retention (compliance requirement for audit trail).
  lifecycle_rule = [
    {
      id      = "retain-audit-7yrs"
      enabled = true
      expiration = { days = 2555 } # ~7 years
    }
  ]
}

resource "aws_kms_key" "s3_data" {
  description             = "KMS key for S3 bucket encryption (data lake + audit)"
  deletion_window_in_days = 30
  enable_key_rotation      = true
}
