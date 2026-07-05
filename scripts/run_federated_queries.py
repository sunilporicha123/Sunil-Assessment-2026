#!/usr/bin/env python3
"""
Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026

run_federated_queries.py
--------------------------
Runs a small suite of validation queries against the live Trino endpoint to
prove the federation layer works end-to-end:
  1. SELECT against the PostgreSQL catalog (DB1)
  2. SELECT against the MySQL catalog (DB2)
  3. A cross-source JOIN between PostgreSQL and MySQL
  4. SHOW CATALOGS / SHOW SCHEMAS to confirm catalog + schema visibility

Used both as a Jenkins smoke test (--smoke-test, exits non-zero on failure)
and as a manual usage example for engineers (see docs/USAGE.md).
"""

import argparse
import logging
import sys

import trino

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("run_federated_queries")


def get_connection(host: str, port: int, user: str) -> trino.dbapi.Connection:
    return trino.dbapi.connect(host=host, port=port, user=user, http_scheme="http")


def run_query(conn, sql: str, label: str) -> list:
    log.info("Running [%s]: %s", label, sql)
    cur = conn.cursor()
    cur.execute(sql)
    rows = cur.fetchall()
    log.info("  -> %d row(s) returned", len(rows))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Run validation queries against the Trino federation layer")
    parser.add_argument("--host", default="trino.sql-federation.svc.cluster.local")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--user", default="ci-smoke-test")
    parser.add_argument("--smoke-test", action="store_true",
                         help="Exit non-zero if any validation query fails")
    args = parser.parse_args()

    conn = get_connection(args.host, args.port, args.user)
    failures = 0

    checks = [
        ("Catalog visibility", "SHOW CATALOGS"),
        ("PostgreSQL source schemas (DB1)", "SHOW SCHEMAS FROM postgresql"),
        ("MySQL source schemas (DB2)", "SHOW SCHEMAS FROM mysql"),
        ("Sample SELECT - PostgreSQL",
         "SELECT * FROM postgresql.public.shipments LIMIT 5"),
        ("Sample SELECT - MySQL",
         "SELECT * FROM mysql.logistics.carriers LIMIT 5"),
        ("Cross-source JOIN (PostgreSQL x MySQL)", """
            SELECT s.shipment_id, s.destination, c.carrier_name
            FROM postgresql.public.shipments s
            JOIN mysql.logistics.carriers c
              ON s.carrier_id = c.carrier_id
            LIMIT 10
        """),
    ]

    for label, sql in checks:
        try:
            run_query(conn, sql, label)
        except Exception as e:
            log.error("Query failed [%s]: %s", label, e)
            failures += 1

    if failures:
        log.error("%d/%d validation queries failed.", failures, len(checks))
        return 1 if args.smoke_test else 0

    log.info("All %d federation validation queries succeeded.", len(checks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
