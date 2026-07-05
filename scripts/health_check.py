#!/usr/bin/env python3
"""
Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026

health_check.py
-----------------
Post-deploy reliability gate used by the Jenkins pipeline. Confirms that
every core deployment in the sql-federation namespace is Ready, and that
Trino's own /v1/info endpoint reports a healthy coordinator, before the
pipeline is allowed to declare a deployment successful.

Usage:
    python3 health_check.py --namespace sql-federation
"""

import argparse
import logging
import sys

import requests
from kubernetes import client, config
from tenacity import retry, stop_after_attempt, wait_fixed

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("health_check")

EXPECTED_DEPLOYMENTS = ["trino-coordinator", "trino-worker", "metabase", "ranger"]


def load_k8s_client():
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.AppsV1Api()


def check_deployments(apps_api, namespace: str) -> bool:
    all_healthy = True
    for name in EXPECTED_DEPLOYMENTS:
        try:
            dep = apps_api.read_namespaced_deployment_status(name, namespace)
        except client.exceptions.ApiException as e:
            log.error("Could not read deployment %s: %s", name, e.reason)
            all_healthy = False
            continue

        desired = dep.spec.replicas or 0
        ready = dep.status.ready_replicas or 0
        status = "OK" if ready == desired and desired > 0 else "UNHEALTHY"
        if status == "UNHEALTHY":
            all_healthy = False
        log.info("Deployment %-20s ready=%s/%s  [%s]", name, ready, desired, status)

    return all_healthy


@retry(stop=stop_after_attempt(5), wait=wait_fixed(10))
def check_trino_endpoint(trino_url: str) -> bool:
    resp = requests.get(f"{trino_url}/v1/info", timeout=5)
    resp.raise_for_status()
    info = resp.json()
    log.info("Trino coordinator reports version=%s, starting=%s",
              info.get("nodeVersion", {}).get("version"), info.get("starting"))
    return not info.get("starting", True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Reliability health check for the SQL federation stack")
    parser.add_argument("--namespace", default="sql-federation")
    parser.add_argument("--trino-url", default="http://trino.sql-federation.svc.cluster.local:8080",
                         help="In-cluster or port-forwarded Trino base URL")
    args = parser.parse_args()

    apps_api = load_k8s_client()
    deployments_ok = check_deployments(apps_api, args.namespace)

    try:
        trino_ok = check_trino_endpoint(args.trino_url)
    except Exception as e:
        log.error("Trino health check failed: %s", e)
        trino_ok = False

    if deployments_ok and trino_ok:
        log.info("All health checks passed.")
        return 0

    log.error("Health check FAILED — deployments_ok=%s, trino_ok=%s", deployments_ok, trino_ok)
    return 1


if __name__ == "__main__":
    sys.exit(main())
