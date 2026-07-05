#!/usr/bin/env python3
"""
Author: Sunil Poricha - Cloud SRE - Technical Assessment 2026

setup_catalogs.py
------------------
Renders Trino catalog .properties files from the templates in
docker/trino/catalog/*.template, substituting values pulled live from AWS
Secrets Manager. This keeps credentials out of ConfigMaps/images entirely —
they exist only as environment variables injected into the pod by the
External Secrets Operator, and are rendered to disk once at container start.

Usage:
    python3 setup_catalogs.py                 # renders catalogs into /etc/trino/catalog
    python3 setup_catalogs.py --verify-only    # dry run: validates required env vars exist
"""

import argparse
import logging
import os
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("setup_catalogs")

TEMPLATE_DIR = Path(os.environ.get("TRINO_CATALOG_TEMPLATE_DIR", "docker/trino/catalog"))
OUTPUT_DIR = Path(os.environ.get("TRINO_CATALOG_OUTPUT_DIR", "/etc/trino/catalog"))

REQUIRED_ENV_VARS = [
    "RDS_POSTGRES_ENDPOINT", "RDS_POSTGRES_DBNAME", "RDS_POSTGRES_USER", "RDS_POSTGRES_PASSWORD",
    "RDS_MYSQL_ENDPOINT", "RDS_MYSQL_DBNAME", "RDS_MYSQL_USER", "RDS_MYSQL_PASSWORD",
]


def verify_env() -> bool:
    missing = [v for v in REQUIRED_ENV_VARS if not os.environ.get(v)]
    if missing:
        log.error("Missing required environment variables: %s", ", ".join(missing))
        return False
    log.info("All required credential environment variables are present.")
    return True


def render_templates() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    templates = list(TEMPLATE_DIR.glob("*.properties.template"))
    if not templates:
        log.warning("No catalog templates found in %s", TEMPLATE_DIR)
        return

    for template_path in templates:
        content = template_path.read_text()
        for key, value in os.environ.items():
            content = content.replace(f"${{{key}}}", value)

        out_name = template_path.name.replace(".template", "")
        out_path = OUTPUT_DIR / out_name
        out_path.write_text(content)
        out_path.chmod(0o600)  # credentials on disk: owner read/write only
        log.info("Rendered catalog: %s -> %s", template_path.name, out_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Trino catalog files from templates + env")
    parser.add_argument("--verify-only", action="store_true",
                         help="Only verify required environment variables are set; do not render files")
    args = parser.parse_args()

    if args.verify_only:
        return 0 if verify_env() else 1

    if not verify_env():
        return 1

    render_templates()
    return 0


if __name__ == "__main__":
    sys.exit(main())
