#!/usr/bin/env python3
"""
Provision CloudWatch Data Sources in Amazon Managed Grafana.

This script dynamically adds a CloudWatch data source for each spoke account,
configured with assume-role ARNs and a 600s minimum scrape interval to prevent
aggressive GetMetricData API calls from inflating client AWS bills.

Usage:
    python provision_datasources.py \
        --grafana-url https://<workspace>.grafana-workspace.<region>.amazonaws.com \
        --api-key <grafana-api-key> \
        --region us-east-1 \
        --spoke-accounts '{"client-alpha":"222222222222","client-bravo":"333333333333"}'

Environment variables (alternative to CLI flags):
    GRAFANA_URL        — Grafana workspace endpoint
    GRAFANA_API_KEY    — Service account token or API key
    AWS_REGION         — Default CloudWatch region
    SPOKE_ACCOUNTS     — JSON object mapping name → account ID
"""

import argparse
import json
import logging
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# CRITICAL: Minimum polling interval to protect client accounts from
# excessive GetMetricData charges.  600 s = 10 minutes.
MIN_INTERVAL_SECONDS = 600

SPOKE_ROLE_NAME = "GrafanaCloudWatchAccessRole"


def grafana_request(base_url: str, api_key: str, method: str, path: str, body: dict | None = None) -> dict:
    """Send an authenticated request to the Grafana HTTP API."""
    url = f"{base_url.rstrip('/')}{path}"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = json.dumps(body).encode() if body else None
    req = Request(url, data=data, headers=headers, method=method)

    try:
        with urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as exc:
        error_body = exc.read().decode() if exc.fp else ""
        logger.error("Grafana API %s %s → %s: %s", method, path, exc.code, error_body)
        raise


def get_existing_datasources(base_url: str, api_key: str) -> dict[str, int]:
    """Return a map of existing data source names → IDs."""
    sources = grafana_request(base_url, api_key, "GET", "/api/datasources")
    return {ds["name"]: ds["id"] for ds in sources}


def upsert_cloudwatch_datasource(
    base_url: str,
    api_key: str,
    name: str,
    account_id: str,
    region: str,
    existing: dict[str, int],
) -> None:
    """Create or update a CloudWatch data source for one spoke account."""
    assume_role_arn = f"arn:aws:iam::{account_id}:role/{SPOKE_ROLE_NAME}"

    payload = {
        "name": name,
        "type": "cloudwatch",
        "access": "proxy",
        "isDefault": False,
        "jsonData": {
            "defaultRegion": region,
            "authType": "assumeRole",
            "assumeRoleArn": assume_role_arn,
            "customMetricsNamespaces": "",
            # CRITICAL: 600 s minimum scrape interval.
            "timeInterval": f"{MIN_INTERVAL_SECONDS}s",
        },
    }

    if name in existing:
        ds_id = existing[name]
        payload["id"] = ds_id
        grafana_request(base_url, api_key, "PUT", f"/api/datasources/{ds_id}", payload)
        logger.info("Updated data source '%s' (id=%d, assume_role=%s)", name, ds_id, assume_role_arn)
    else:
        result = grafana_request(base_url, api_key, "POST", "/api/datasources", payload)
        logger.info("Created data source '%s' (id=%s, assume_role=%s)", name, result.get("id"), assume_role_arn)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Provision CloudWatch data sources in Amazon Managed Grafana"
    )
    parser.add_argument(
        "--grafana-url",
        default=os.environ.get("GRAFANA_URL", ""),
        help="Grafana workspace URL (or set GRAFANA_URL env var)",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("GRAFANA_API_KEY", ""),
        help="Grafana API key (or set GRAFANA_API_KEY env var)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "us-east-1"),
        help="Default AWS region for CloudWatch queries",
    )
    parser.add_argument(
        "--spoke-accounts",
        default=os.environ.get("SPOKE_ACCOUNTS", "{}"),
        help='JSON object: {"friendly-name": "account-id", ...}',
    )

    args = parser.parse_args()

    if not args.grafana_url:
        logger.error("--grafana-url or GRAFANA_URL is required")
        sys.exit(1)
    if not args.api_key:
        logger.error("--api-key or GRAFANA_API_KEY is required")
        sys.exit(1)

    try:
        spoke_accounts: dict[str, str] = json.loads(args.spoke_accounts)
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in --spoke-accounts: %s", exc)
        sys.exit(1)

    if not spoke_accounts:
        logger.warning("No spoke accounts provided — nothing to provision.")
        sys.exit(0)

    logger.info(
        "Provisioning %d CloudWatch data source(s) in %s",
        len(spoke_accounts),
        args.grafana_url,
    )
    logger.info("Minimum scrape interval: %ds (protects client billing)", MIN_INTERVAL_SECONDS)

    existing = get_existing_datasources(args.grafana_url, args.api_key)

    for friendly_name, account_id in spoke_accounts.items():
        ds_name = f"CloudWatch-{friendly_name}"
        upsert_cloudwatch_datasource(
            base_url=args.grafana_url,
            api_key=args.api_key,
            name=ds_name,
            account_id=account_id,
            region=args.region,
            existing=existing,
        )

    logger.info("Done. All data sources provisioned with %ds minimum interval.", MIN_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
