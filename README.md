# Hub-and-Spoke Observability with Amazon Managed Grafana

Multi-account AWS observability using a central **Amazon Managed Grafana** workspace (hub) that queries **CloudWatch** metrics in client accounts (spokes) via cross-account IAM role assumption.

```
┌─────────────────────────────────────────────────────────────┐
│  Hub Account (MSP)                                          │
│                                                             │
│  ┌──────────────────────┐   sts:AssumeRole                  │
│  │  Amazon Managed       │──────────────┐                    │
│  │  Grafana Workspace    │              │                    │
│  │  (GrafanaWorkspaceRole)│             │                    │
│  └──────────────────────┘              │                    │
└─────────────────────────────────────────┼───────────────────┘
                                          │
          ┌───────────────────────────────┼──────────────────┐
          │                               │                  │
          ▼                               ▼                  ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ Spoke Account A  │  │ Spoke Account B  │  │ Spoke Account C  │
│                  │  │                  │  │                  │
│ GrafanaCloudWatch│  │ GrafanaCloudWatch│  │ GrafanaCloudWatch│
│ AccessRole       │  │ AccessRole       │  │ AccessRole       │
│ (CloudWatch RO)  │  │ (CloudWatch RO)  │  │ (CloudWatch RO)  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

## Directory Structure

```
.
├── main.tf                          # Root — wires hub + spoke modules + data sources
├── providers.tf                     # AWS & Grafana provider configuration
├── variables.tf                     # Root input variables
├── outputs.tf                       # Root outputs
├── terraform.tfvars.example         # Example variable values
├── .gitignore
├── modules/
│   ├── hub/
│   │   ├── main.tf                  # Grafana workspace + IAM role
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── spoke/
│       ├── main.tf                  # Cross-account IAM role
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    ├── provision_datasources.py     # Standalone provisioning script
    └── requirements.txt
```

## Prerequisites

- **Terraform** >= 1.5
- **AWS CLI** configured with named profiles for each account
- **AWS IAM Identity Center** (SSO) enabled in the hub account
- **Python 3.10+** (only for the standalone provisioning script)

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your account IDs and profile names:

```hcl
hub_aws_profile = "msp-hub"
hub_account_id  = "111111111111"

spoke_accounts = {
  "client-alpha"   = "222222222222"
  "client-bravo"   = "333333333333"
  "client-charlie" = "444444444444"
}
```

### 2. First Apply — Infrastructure

> **Important:** The spoke module instances require AWS providers configured for
> each client account. See [Multi-Account Provider Setup](#multi-account-provider-setup) below.

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

This creates:
- The Amazon Managed Grafana workspace in the hub account
- The `GrafanaWorkspaceRole` with cross-account assume permissions
- The `GrafanaCloudWatchAccessRole` in each spoke account

### 3. Generate a Grafana API Key

1. Open the Grafana workspace URL from the Terraform output.
2. Navigate to **Administration → Service Accounts → Add service account**.
3. Create a token with **Admin** role.
4. Add the token to `terraform.tfvars`:

```hcl
grafana_api_key = "glsa_xxxxxxxxxxxx"
```

### 4. Second Apply — Data Sources

```bash
terraform apply
```

This provisions the `CloudWatch-<client-name>` data sources in Grafana, each
configured with:
- `assumeRoleArn` pointing to the spoke's `GrafanaCloudWatchAccessRole`
- `timeInterval = 600s` (10-minute minimum scrape interval to protect client billing)

## Multi-Account Provider Setup

The spoke modules need AWS credentials for each client account. There are two approaches:

### Option A: Per-Account Provider Aliases (Recommended for < 20 accounts)

Add provider aliases in `providers.tf`:

```hcl
provider "aws" {
  alias   = "client_alpha"
  region  = var.aws_region
  profile = "client-alpha"
}
```

Then pass them to each spoke module in `main.tf`:

```hcl
module "spoke" {
  source   = "./modules/spoke"
  for_each = var.spoke_accounts

  providers = {
    aws = aws.${each.key}   # requires static aliases — see option B
  }

  hub_grafana_role_arn = module.hub.grafana_role_arn
}
```

### Option B: Separate Terraform Workspaces (Recommended for many accounts)

Deploy the spoke module independently per account:

```bash
# For each client account
cd modules/spoke
AWS_PROFILE=client-alpha terraform init
AWS_PROFILE=client-alpha terraform apply \
  -var="hub_grafana_role_arn=arn:aws:iam::111111111111:role/GrafanaWorkspaceRole"
```

## Alternative: Python Provisioning Script

If you prefer to manage data sources outside Terraform:

```bash
python scripts/provision_datasources.py \
  --grafana-url "https://g-abc123.grafana-workspace.us-east-1.amazonaws.com" \
  --api-key "glsa_xxxxxxxxxxxx" \
  --region us-east-1 \
  --spoke-accounts '{"client-alpha":"222222222222","client-bravo":"333333333333"}'
```

The script is idempotent — it creates or updates data sources as needed.

## Billing Protection

**CRITICAL:** All CloudWatch data sources are configured with a **600-second (10-minute)
minimum scrape interval** (`timeInterval`). This prevents Grafana dashboards from
issuing aggressive `GetMetricData` API calls that would spike client AWS bills.

This is enforced in:
- `main.tf` — the `grafana_data_source` resource sets `timeInterval = "600s"`
- `scripts/provision_datasources.py` — the `MIN_INTERVAL_SECONDS = 600` constant

> **Do not lower this value** without understanding the billing impact on client accounts.

## Security Design

| Principle | Implementation |
|---|---|
| **Least privilege** | Spoke roles have only `CloudWatchReadOnlyAccess` (AWS managed policy) |
| **Explicit trust** | Spoke trust policies name only the hub's `GrafanaWorkspaceRole` ARN |
| **Service scoping** | Hub role trust policy restricts to `grafana.amazonaws.com` + source account condition |
| **Optional external ID** | Spoke module accepts an `external_id` variable for confused-deputy protection |
| **No wildcard resources** | Hub assume-role policy lists each spoke role ARN explicitly |
| **SSO authentication** | Grafana workspace uses AWS IAM Identity Center — no local passwords |

## Outputs

| Output | Description |
|---|---|
| `grafana_workspace_endpoint` | Grafana workspace URL |
| `grafana_workspace_id` | Grafana workspace ID |
| `hub_grafana_role_arn` | Hub IAM role ARN (needed by spoke modules) |
| `spoke_role_arns` | Map of spoke name → IAM role ARN |

## Adding a New Client Account

1. Add the account to `spoke_accounts` in `terraform.tfvars`:
   ```hcl
   spoke_accounts = {
     # existing accounts ...
     "client-delta" = "555555555555"
   }
   ```
2. Run `terraform apply` — this creates the spoke IAM role and updates the hub
   policy and Grafana data source in a single apply.
