# Usage Guide

<!-- Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026 -->

## 1. Accessing the Federation UI / CLI

- **Metabase (Business Dashboards)**: `https://dashboards.datawave.internal` — Cognito
  login required at the ALB before Metabase's own login page appears.
- **Trino Web UI**: `https://trino.datawave.internal` — also Cognito-gated; shows live
  query execution, worker status, and cluster resource usage.
- **Trino CLI** (for engineers, via port-forward):
  ```bash
  kubectl port-forward svc/trino 8080:8080 -n sql-federation
  trino --server http://localhost:8080 --user <your-username>
  ```

## 2. Example SQL Queries

**List available catalogs (confirms all three sources are federated):**
```sql
SHOW CATALOGS;
-- expected: postgresql, mysql, s3_datalake, system
```

**Query DB1 (PostgreSQL) directly:**
```sql
SELECT shipment_id, origin, destination, status
FROM postgresql.public.shipments
WHERE status = 'IN_TRANSIT'
LIMIT 20;
```

**Query DB2 (MySQL) directly:**
```sql
SELECT carrier_id, carrier_name, region
FROM mysql.logistics.carriers;
```

**Federated join across PostgreSQL and MySQL — this is the core capability the
federation layer exists to provide:**
```sql
SELECT s.shipment_id, s.destination, c.carrier_name, c.region
FROM postgresql.public.shipments s
JOIN mysql.logistics.carriers c
  ON s.carrier_id = c.carrier_id
WHERE s.status = 'IN_TRANSIT';
```

**Query the S3 data lake catalog:**
```sql
SELECT *
FROM s3_datalake.tracking.shipment_events
WHERE event_date >= DATE '2026-06-01'
LIMIT 50;
```

Run all of the above automatically with:
```bash
python3 scripts/run_federated_queries.py --host localhost --port 8080 --user demo
```

## 3. Adding a New Connector

1. Add a new template file to `docker/trino/catalog/<name>.properties.template`,
   following the pattern in the existing PostgreSQL/MySQL templates.
2. Add the corresponding entry to `k8s/trino/configmap-catalogs.yaml`.
3. If the source needs credentials, add a new secret path under
   `datawave/rds/<name>` in Secrets Manager and a matching `data` entry in
   `k8s/secrets/secrets-template.yaml`.
4. `scripts/setup_catalogs.py` will automatically pick up and render any new
   `*.properties.template` file — no code changes needed there.
5. Redeploy: `kubectl rollout restart deployment/trino-coordinator deployment/trino-worker -n sql-federation`.

## 4. SSO Documentation

**Provider**: AWS Cognito, using the OpenID Connect (OIDC) protocol.

**Authentication flow:**
1. User requests `https://dashboards.datawave.internal`.
2. ALB Ingress (`k8s/ingress.yaml`) intercepts the request and, if no valid session
   cookie is present, redirects to the Cognito Hosted UI.
3. User authenticates with Cognito (username/password, or a federated upstream IdP if
   Cognito is configured with one).
4. Cognito redirects back to the ALB with an authorization code; the ALB exchanges it
   for tokens and sets a signed session cookie, then forwards the original request to
   Metabase/Trino with identity claims in the `x-amzn-oidc-*` headers.
5. **Ranger** independently syncs users/groups from the same Cognito User Pool on a
   scheduled job, so authorization policies (table/column/row-level grants) stay aligned
   with the identity source of truth without manual user provisioning in Ranger itself.

**Configuration steps** (summary — see `k8s/ranger/deployment.yaml` and
`k8s/ingress.yaml` for the exact fields):
1. Create a Cognito User Pool and App Client (confidential client, with a client secret).
2. Store the client secret in Secrets Manager at `datawave/sso/cognito` → `client_secret`.
3. Set the pool ARN, App Client ID, and Cognito domain in the ALB Ingress annotations.
4. Set `RANGER_OIDC_ISSUER_URL` / `RANGER_OIDC_CLIENT_ID` via the `sso-config` ConfigMap.
5. Redeploy the ingress and Ranger: `kubectl apply -f k8s/ingress.yaml -f k8s/ranger/`.

## 5. Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `kubectl get pods` shows Trino `CrashLoopBackOff` | Missing/incorrect Secrets Manager values | `kubectl logs deploy/trino-coordinator -n sql-federation`; verify `ExternalSecret` synced: `kubectl get externalsecret -n sql-federation` |
| `SHOW CATALOGS` doesn't list a source | Catalog file not rendered correctly | `kubectl exec -it deploy/trino-coordinator -n sql-federation -- cat /etc/trino/catalog/<name>.properties` |
| Cross-source JOIN times out | Large table scan on one side with no pushdown | Add filters (`WHERE`) that Trino can push down per-connector; check `EXPLAIN` plan |
| ALB returns 502 | Target group unhealthy / readiness probe failing | `kubectl describe pod -n sql-federation <pod>`; check `readinessProbe` path/port |
| Cognito login loops | App Client redirect URI mismatch | Confirm the Cognito App Client's callback URL exactly matches the ALB's configured domain |
| `terraform apply` fails on RDS security group rule | `rds_postgres_sg_id` / `rds_mysql_sg_id` incorrect in tfvars | Confirm SG IDs via `aws rds describe-db-instances --db-instance-identifier datawave-db1-postgres` |
