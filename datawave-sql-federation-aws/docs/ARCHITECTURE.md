# Architecture Overview

<!-- Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026 -->

## 1. Reference Diagram

This implementation maps 1:1 onto the DataWave SQL Federation Architecture diagram
provided in the technical case: three data sources feeding Trino, Apache Ranger for
policy enforcement with SSO-synced users/groups, an Elasticsearch audit sink, and
Metabase serving business dashboards and employees.

## 2. Component-by-Component Mapping

### 2.1 Data Sources (DB1 / DB2 / DB3)
- **DB1 — PostgreSQL**: An existing Amazon RDS PostgreSQL instance (per the assignment,
  RDS is assumed already provisioned; see `terraform/rds_data.tf`, which references it
  as a data source rather than creating it).
- **DB2 — MySQL**: An existing Amazon RDS MySQL instance, referenced the same way.
- **DB3 — Object storage source**: Implemented as **Amazon S3** + **AWS Glue Data
  Catalog**, queried through Trino's Hive connector (`docker/trino/catalog/s3_datalake.properties.template`).
  This satisfies the case's "MinIO/S3 (optional but preferred)" requirement using a
  fully managed AWS equivalent.

### 2.2 SQL Federation Engine — Trino
Deployed as a coordinator + worker `Deployment` on EKS (`k8s/trino/deployment.yaml`),
horizontally scaled via HPA on CPU utilization. Catalog configuration is split into:
- **Non-secret structure** (connector name, tuning flags) — Kubernetes ConfigMap.
- **Secrets** (endpoints, usernames, passwords) — pulled from AWS Secrets Manager at
  runtime by the External Secrets Operator, then rendered into catalog files by
  `scripts/setup_catalogs.py`. No credential ever appears in a manifest, image, or Git
  history.

### 2.3 Metadata / Catalog Layer
Trino's own catalog mechanism handles PostgreSQL/MySQL; for the S3 source, **AWS Glue
Data Catalog** acts as the Hive-compatible metastore, avoiding the need to self-host a
Hive Metastore service.

### 2.4 Apache Ranger (Policy / Governance)
Deployed on EKS (`k8s/ranger/deployment.yaml`) as the authorization plugin for Trino,
enforcing table/column/row-level policies. Ranger syncs users and groups from **AWS
Cognito** via OIDC — replacing the generic "SSO" box in the diagram with a concrete AWS
service.

### 2.5 SSO Integration (Extra Credit)
- **Identity Provider**: AWS Cognito User Pool.
- **Flow**: OpenID Connect (OIDC). The ALB Ingress Controller performs the initial
  Cognito authentication challenge at the load balancer (`k8s/ingress.yaml`,
  `alb.ingress.kubernetes.io/auth-type: cognito`) before any request reaches a pod.
  Ranger additionally validates the OIDC token for fine-grained authorization
  decisions, and syncs group membership from Cognito on a scheduled interval.
- This means **unauthenticated traffic never reaches Trino, Ranger, or Metabase** — the
  first hop is always the identity provider.

### 2.6 Audit Layer — Elasticsearch
A Trino event listener plugin (`docker/trino/etc/event-listener.properties`, baked into
the custom image) ships every query event — query text, user, tables touched, duration,
success/failure — to Elasticsearch, deployed as a `StatefulSet`
(`k8s/elasticsearch/statefulset.yaml`) with persistent `gp3` volumes.

**Production note**: for a production rollout, this StatefulSet should be replaced with
the managed **Amazon OpenSearch Service**, removing the operational burden of patching,
scaling, and snapshotting a self-hosted cluster. It is kept self-managed here to mirror
the diagram's "elasticsearch" box directly and to keep the assessment's infra fully
described in this repo's Terraform/K8s code.

### 2.7 Consumption Layer — Metabase → Business Dashboards & Employees
Metabase connects to Trino as its query engine and is exposed externally through the ALB
Ingress with TLS termination and Cognito authentication, matching the diagram's two
downstream consumers (Business Dashboards, Employees) as a single governed entry point.

## 3. Request Flow (End-to-End)

1. A user (employee or dashboard) hits `dashboards.datawave.internal` over HTTPS.
2. ALB terminates TLS and challenges the user via Cognito (OIDC) if not already
   authenticated.
3. Request reaches the Metabase pod, which issues SQL to Trino.
4. Trino consults Ranger to authorize the request against the user's synced
   Cognito group membership and configured policies.
5. Trino fans the query out to the relevant catalogs (PostgreSQL / MySQL / S3+Glue),
   executes any joins/aggregations in its own engine, and returns results.
6. The Trino event listener asynchronously ships the query's audit record to
   Elasticsearch.

## 4. Reliability & Scalability Choices

- **Multi-AZ EKS** node group spread across 3 AZs (`terraform/variables.tf` `azs`).
- **HPA** on Trino workers absorbs bursty analytical load without manual intervention.
- **Readiness/liveness probes** on every workload so Kubernetes only routes traffic to
  pods that are actually able to serve it.
- **Rollback on failure**: the Jenkins pipeline automatically runs
  `kubectl rollout undo` if post-deploy smoke tests fail (`jenkins/Jenkinsfile`, `post.failure`).
- **VPC Flow Logs + audit bucket** give a durable record for incident investigation,
  independent of the application-level Elasticsearch audit trail.

## 5. Security Best Practices Applied

| Area | Practice |
|---|---|
| Secrets | AWS Secrets Manager + External Secrets Operator; zero plaintext credentials in Git, images, or ConfigMaps |
| IAM | IRSA (per-pod IAM roles) instead of broad node-level permissions; every policy scoped to specific ARNs |
| Network | Private EKS API endpoint; RDS security groups only accept traffic from the EKS node SG; Kubernetes NetworkPolicies restrict pod-to-pod traffic (only Metabase/Ranger → Trino) |
| Data at rest | S3 SSE-KMS with key rotation; EKS secrets envelope-encrypted with a dedicated KMS key |
| Data in transit | TLS termination at ALB with ACM certificate; internal cluster traffic isolated within the VPC |
| Identity | Centralized SSO via Cognito/OIDC for both the UI (ALB auth) and the authorization engine (Ranger) |
| Supply chain | Jenkins pipeline runs `tfsec` on Terraform and `trivy` on the built container image, failing the build on HIGH/CRITICAL findings |
| Least privilege | Every IAM policy in `terraform/iam.tf` / `terraform/eks.tf` lists explicit actions and resource ARNs — no wildcards |
| Auditability | Full query audit trail (Elasticsearch) + infrastructure audit trail (VPC Flow Logs to S3) + EKS control-plane audit logs enabled |
