# Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026
#
# Per the assignment, RDS instances are ASSUMED TO ALREADY EXIST and are not
# created by this stack. We reference them here purely as data for validation
# and to make the dependency explicit and documented, rather than provisioning
# new databases.

data "aws_db_instance" "postgres_source" {
  # DB identifier of the existing PostgreSQL RDS instance representing DB1
  db_instance_identifier = "datawave-db1-postgres"
}

data "aws_db_instance" "mysql_source" {
  # DB identifier of the existing MySQL RDS instance representing DB2
  db_instance_identifier = "datawave-db2-mysql"
}

# These outputs are consumed by the Kubernetes manifests (via Terraform ->
# Helm/kustomize value injection, or manually copied into k8s/trino/configmap-catalogs.yaml)
# so Trino's catalog properties always point at the live RDS endpoints.
