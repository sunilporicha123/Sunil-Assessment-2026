# DataWave SQL Federation Architecture — AWS Cloud Implementation

<!-- Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026 -->

This repository implements the DataWave Industries SQL Federation Layer on **AWS**,
replacing the local Docker Compose simulation described in the technical case with a
production-oriented, cloud-native deployment on **Amazon EKS**, backed by **Amazon RDS**
sources, **Amazon S3** for object storage / lake data, and secured with IAM, Kubernetes
network policies, and TLS.

The federation engine (Trino), governance layer (Apache Ranger), audit layer
(Elasticsearch), and consumption layer (Metabase) all run as containerized workloads on
EKS, deployed and configured with Terraform, Kubernetes manifests, and a Jenkins CI/CD
pipeline.

## 1. Why AWS instead of local Docker Compose

The technical case asks for a local simulation of the architecture. This implementation
goes one step further and demonstrates how the same architecture would be **operated
reliably in production**, which is the core competency being assessed for a Staff Data
Reliability Engineer role:

| Local (Docker Compose) | AWS Production Equivalent |
|---|---|
| Single host, no HA | Multi-AZ EKS node groups, pod anti-affinity |
| Local Postgres/MySQL containers | Existing AWS RDS instances (assumed provisioned) |
| Local volumes | Amazon S3 (data lake / audit archive), EBS via `gp3` StorageClass |
| No secrets management | AWS Secrets Manager + Kubernetes External Secrets |
| No CI/CD | Jenkins pipeline: lint → plan → image build → deploy → smoke test |
| Manual scaling | Cluster Autoscaler / Karpenter + HPA on Trino workers |
| No audit trail | Elasticsearch + Trino event listener, shipped to S3 for long-term retention |

## 2. Repository Layout

```
datawave-sql-federation-aws/
├── terraform/          # AWS infrastructure: VPC, EKS, S3, IAM, Security Groups
├── docker/              # Custom Trino image + catalog templates
├── k8s/                 # Kubernetes manifests for all federation components
├── jenkins/             # Jenkinsfile — full CI/CD pipeline
├── scripts/             # Python automation: catalog setup, health checks, query tests
└── docs/                # Architecture, Setup, and Usage documentation
```

## 3. Quick Links

- [Architecture Overview](docs/ARCHITECTURE.md)
- [Setup Instructions](docs/SETUP.md)
- [Usage Guide](docs/USAGE.md)

## 4. High-Level Component Mapping

| Diagram Component | AWS Implementation |
|---|---|
| DB1 / DB2 / DB3 (Sources) | Amazon RDS (PostgreSQL, MySQL) + S3 (via Trino Hive/Delta connector) |
| Trino | Deployment on EKS (coordinator + worker pods), HPA-scaled |
| Apache Ranger | Deployment on EKS, policies stored in its own RDS-backed metastore |
| SSO | AWS Cognito / OIDC → Ranger & Trino OAuth2 authenticator |
| Elasticsearch (Audit) | Amazon OpenSearch Service (or self-managed ES StatefulSet on EKS) |
| Metabase | Deployment on EKS, exposed via ALB Ingress |
| Business Dashboards / Employees | ALB Ingress + Cognito-authenticated access |

## 5. Security Posture Summary

See `terraform/security_groups.tf`, `terraform/iam.tf`, and `docs/ARCHITECTURE.md` §5 for
full detail. In brief:

- No plaintext credentials anywhere in the repo — all secrets pulled from **AWS Secrets
  Manager** at runtime via the Kubernetes External Secrets Operator.
- EKS control plane private endpoint + restricted public CIDR allow-list.
- IAM roles scoped with least privilege via **IRSA** (IAM Roles for Service Accounts) —
  no node-wide IAM permissions.
- All S3 buckets: encryption at rest (SSE-KMS), versioning enabled, public access blocked.
- Network segmentation via Kubernetes `NetworkPolicy` — only Trino may reach RDS security
  groups; only Metabase may reach Trino.
- TLS termination at the ALB Ingress; internal traffic within the cluster uses ClusterIP
  services (mTLS optional via service mesh, noted as a future enhancement).

---
*Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026*
