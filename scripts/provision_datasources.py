#!/usr/bin/env python3
"""
Provision CloudWatch data sources in a Grafana Cloud stack.

Grafana Cloud authenticates to customer AWS accounts by chain-assuming a role
through Grafana Labs' production AWS account. The data source configuration
uses authType="grafana_assume_role" plus an External ID that must match the
spoke IAM trust policy.

Usage:
    python provision_datasources.py \
        --stack-url https://mycompany.grafana.net \
        --sa-token glsa_xxxxxxxxxxxx \
        --region us-east-1 \
        --external-id 3f8b9d0e-1a2b-4c5d-9e6f-7a8b9c0d1e2f \
        --spoke-accounts '{"client-alpha":"222222222222","client-bravo":"333333333333"}'

Environment variables (alternative to CLI flags):
    GRAFANA_CLOUD_STACK_URL   — stack URL (e.g. https://mycompany.grafana.net)
    GRAFANA_CLOUD_SA_TOKEN    — stack service account token (Admin role)
    AWS_REGION                — default CloudWatch region
    GRAFANA_EXTERNAL_ID       — External ID matching the spoke trust policies
    SPOKE_ACCOUNTS            — JSON: {"friendly-name": "account-id", ...}
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
# excessive GetMetricData charges. 600 s = 10 minutes.
MIN_INTERVAL_SECONDS = 600

SPOKE_ROLE_NAME = "GrafanaCloudWatchAccessRole"


def grafana_request(
    base_url: str, api_key: str, method: str, path: str, body: dict | None = None
) -> dict:
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
    external_id: str,
    existing: dict[str, int],
) -> None:
    """Create or update a Grafana Cloud CloudWatch data source for one spoke."""
    assume_role_arn = f"arn:aws:iam::{account_id}:role/{SPOKE_ROLE_NAME}"

    payload = {
        "name": name,
        "type": "cloudwatch",
        "access": "proxy",
        "isDefault": False,
        "jsonData": {
            "defaultRegion": region,
            # Grafana Cloud-specific auth: chain-assume through Grafana Labs' AWS account.
            "authType": "grafana_assume_role",
            "assumeRoleArn": assume_role_arn,
            "externalId": external_id,
            "customMetricsNamespaces": "",
            # CRITICAL: 600 s minimum scrape interval.
            "timeInterval": f"{MIN_INTERVAL_SECONDS}s",
        },
    }

    if name in existing:
        ds_id = existing[name]
        payload["id"] = ds_id
        grafana_request(base_url, api_key, "PUT", f"/api/datasources/{ds_id}", payload)
        logger.info(
            "Updated data source '%s' (id=%d, assume_role=%s)",
            name,
            ds_id,
            assume_role_arn,
        )
    else:
        result = grafana_request(base_url, api_key, "POST", "/api/datasources", payload)
        logger.info(
            "Created data source '%s' (id=%s, assume_role=%s)",
            name,
            result.get("id"),
            assume_role_arn,
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Provision CloudWatch data sources in a Grafana Cloud stack"
    )
    parser.add_argument(
        "--stack-url",
        default=os.environ.get("GRAFANA_CLOUD_STACK_URL", ""),
        help="Grafana Cloud stack URL (or set GRAFANA_CLOUD_STACK_URL)",
    )
    parser.add_argument(
        "--sa-token",
        default=os.environ.get("GRAFANA_CLOUD_SA_TOKEN", ""),
        help="Grafana Cloud service account token (or set GRAFANA_CLOUD_SA_TOKEN)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "us-east-1"),
        help="Default AWS region for CloudWatch queries",
    )
    parser.add_argument(
        "--external-id",
        default=os.environ.get("GRAFANA_EXTERNAL_ID", ""),
        help="External ID matching spoke IAM trust policies (or set GRAFANA_EXTERNAL_ID)",
    )
    parser.add_argument(
        "--spoke-accounts",
        default=os.environ.get("SPOKE_ACCOUNTS", "{}"),
        help='JSON object: {"friendly-name": "account-id", ...}',
    )

    args = parser.parse_args()

    missing = []
    if not args.stack_url:
        missing.append("--stack-url / GRAFANA_CLOUD_STACK_URL")
    if not args.sa_token:
        missing.append("--sa-token / GRAFANA_CLOUD_SA_TOKEN")
    if not args.external_id:
        missing.append("--external-id / GRAFANA_EXTERNAL_ID")
    if missing:
        logger.error("Missing required argument(s): %s", ", ".join(missing))
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
        args.stack_url,
    )
    logger.info("Minimum scrape interval: %ds (protects client billing)", MIN_INTERVAL_SECONDS)

    existing = get_existing_datasources(args.stack_url, args.sa_token)

    for friendly_name, account_id in spoke_accounts.items():
        ds_name = f"CloudWatch-{friendly_name}"
        upsert_cloudwatch_datasource(
            base_url=args.stack_url,
            api_key=args.sa_token,
            name=ds_name,
            account_id=account_id,
            region=args.region,
            external_id=args.external_id,
            existing=existing,
        )

    logger.info("Done. All data sources provisioned with %ds minimum interval.", MIN_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
