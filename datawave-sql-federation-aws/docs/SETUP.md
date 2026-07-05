# Setup Instructions

<!-- Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026 -->

## 1. Prerequisites

- AWS account with permissions to create VPC, EKS, S3, IAM, KMS, and read existing RDS resources
- Two existing RDS instances (assumed already provisioned, per the assignment):
  - PostgreSQL instance, DB identifier `datawave-db1-postgres`
  - MySQL instance, DB identifier `datawave-db2-mysql`
- Credentials for both RDS instances stored in **AWS Secrets Manager** under:
  - `datawave/rds/postgres` (keys: `endpoint`, `dbname`, `username`, `password`)
  - `datawave/rds/mysql` (keys: `endpoint`, `dbname`, `username`, `password`)
- Tools installed locally: `terraform >= 1.6`, `aws-cli v2`, `kubectl >= 1.29`, `docker`,
  `python3.11+`, `helm` (for AWS Load Balancer Controller and External Secrets Operator)
- An AWS Cognito User Pool if you intend to enable the optional SSO integration

## 2. Clone the Repository

```bash
git clone https://github.com/<your-org>/datawave-sql-federation-aws.git
cd datawave-sql-federation-aws
```

## 3. Configure Terraform Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: fill in RDS endpoints, security group IDs, and Secrets Manager ARNs
```

## 4. Provision AWS Infrastructure

```bash
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

This creates: VPC + subnets across 3 AZs, EKS cluster with a managed node group, S3
buckets (data lake + audit), KMS keys, IAM/IRSA roles, and security group rules that open
the existing RDS instances to traffic from the new EKS node security group only.

```bash
terraform output configure_kubectl
# run the printed command, e.g.:
aws eks update-kubeconfig --region us-east-1 --name datawave-federation-eks
```

## 5. Install Cluster Add-ons

```bash
# AWS Load Balancer Controller (for the ALB Ingress)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=datawave-federation-eks \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform -chdir=terraform output -raw alb_controller_irsa_role_arn 2>/dev/null || echo "<see terraform output>")

# External Secrets Operator (syncs Secrets Manager -> Kubernetes Secrets)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n sql-federation --create-namespace
```

## 6. Build and Push the Trino Image

This step normally runs automatically in the Jenkins pipeline (`jenkins/Jenkinsfile`),
but can be run manually:

```bash
aws ecr create-repository --repository-name datawave/trino-federation --region us-east-1 || true
aws ecr get-login-password --region us-east-1 | docker login --username AWS \
  --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/datawave/trino-federation:latest \
  -f docker/trino/Dockerfile docker/trino/

docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/datawave/trino-federation:latest
```

## 7. Deploy the Federation Stack to EKS

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets/secrets-template.yaml
kubectl apply -f k8s/trino/
kubectl apply -f k8s/ranger/
kubectl apply -f k8s/elasticsearch/
kubectl apply -f k8s/metabase/
kubectl apply -f k8s/ingress.yaml
```

## 8. Confirm All Services Are Operational

```bash
kubectl get pods -n sql-federation
kubectl rollout status deployment/trino-coordinator -n sql-federation
kubectl rollout status deployment/metabase -n sql-federation

# Python-based health check (also run automatically by Jenkins post-deploy)
pip install -r scripts/requirements.txt
python3 scripts/health_check.py --namespace sql-federation
```

Expected output: every deployment reports `ready == desired` and the Trino
`/v1/info` endpoint returns `"starting": false`.

## 9. Set Up CI/CD (Jenkins)

1. Create a Jenkins multibranch pipeline pointing at this repository; it will
   auto-discover `jenkins/Jenkinsfile`.
2. Configure Jenkins credentials: an IAM role/OIDC federation allowing the Jenkins
   agent to assume `terraform/iam.tf`'s `jenkins_deploy` role (scoped to ECR push and
   `eks:DescribeCluster` only).
3. Push to any branch to trigger lint/plan/build/scan; merging to `main` adds a manual
   approval gate before `terraform apply` and the EKS deployment run.

## 10. Tear Down

```bash
kubectl delete -f k8s/ingress.yaml -f k8s/metabase/ -f k8s/elasticsearch/ -f k8s/ranger/ -f k8s/trino/ -f k8s/secrets/secrets-template.yaml -f k8s/namespace.yaml
cd terraform && terraform destroy -var-file=terraform.tfvars
```
(RDS instances are never touched by this stack and are unaffected by `terraform destroy`.)
