# Hub-and-Spoke Observability with Grafana Cloud

Multi-account AWS observability using a central **Grafana Cloud** stack (hub) that queries **CloudWatch** metrics in client accounts (spokes) via cross-account IAM role assumption.

```
┌───────────────────────────────────┐
│  Grafana Cloud (Grafana Labs SaaS)│
│  https://<org>.grafana.net        │
│                                   │
│  Runs in Grafana Labs' AWS acct   │
│  (008923505280)                   │
└─────────────┬─────────────────────┘
              │ sts:AssumeRole
              │ (with ExternalId)
    ┌─────────┼─────────────┬─────────────┐
    ▼         ▼             ▼             ▼
┌────────┐ ┌────────┐  ┌────────┐  ┌────────┐
│ Spoke  │ │ Spoke  │  │ Spoke  │  │ Spoke  │
│ Acct A │ │ Acct B │  │ Acct C │  │ Acct D │
│        │ │        │  │        │  │        │
│ Grafana│ │ Grafana│  │ Grafana│  │ Grafana│
│ Cloud  │ │ Cloud  │  │ Cloud  │  │ Cloud  │
│ Watch  │ │ Watch  │  │ Watch  │  │ Watch  │
│ Access │ │ Access │  │ Access │  │ Access │
│ Role   │ │ Role   │  │ Role   │  │ Role   │
└────────┘ └────────┘  └────────┘  └────────┘
```

## Why Grafana Cloud (vs. Amazon Managed Grafana)?

| | Grafana Cloud | Amazon Managed Grafana |
|---|---|---|
| **Hosted by** | Grafana Labs | AWS |
| **Auth** | Service account tokens / OAuth / SAML | AWS IAM Identity Center |
| **AWS auth model** | Chain-assume via Grafana Labs' AWS account + External ID | In-account role |
| **Alerting** | Grafana Alerting included | Additional feature |
| **Synthetic monitoring / OnCall** | Included | Not available |
| **Logs/traces** | Loki + Tempo included | BYO |
| **Cost model** | Active users + data ingest | Per active user |

## Directory Structure

```
.
├── main.tf                          # Root — spoke modules + Grafana Cloud data sources
├── providers.tf                     # AWS + Grafana providers
├── variables.tf                     # Root input variables
├── outputs.tf                       # Root outputs
├── terraform.tfvars.example         # Example variable values
├── .gitignore
├── modules/
│   └── spoke/
│       ├── main.tf                  # IAM role trusting Grafana Labs AWS account
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    ├── provision_datasources.py     # Standalone Python provisioner
    └── requirements.txt
```

## Prerequisites

- **Terraform** >= 1.5
- **Grafana Cloud account** with a stack created (free tier works for testing)
- **AWS CLI** configured with credentials that can create IAM in each spoke account
- **Python 3.10+** (only for the standalone provisioning script)

## Quick Start

### 1. Create a Grafana Cloud Stack

If you don't already have a stack:

1. Sign up at <https://grafana.com/products/cloud/>
2. Create a stack — note its URL (e.g. `https://mycompany.grafana.net`).
3. In the stack: **Administration → Service accounts → Add service account**
   - Role: **Admin** (required for data-source provisioning)
   - Generate a token — copy the `glsa_...` value.

### 2. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
aws_profile = "org-management"

spoke_accounts = {
  "client-alpha"   = "222222222222"
  "client-bravo"   = "333333333333"
  "client-charlie" = "444444444444"
}

grafana_cloud_stack_url = "https://mycompany.grafana.net"
```

Keep the service account token out of the file — export it instead:

```bash
export TF_VAR_grafana_cloud_stack_sa_token="glsa_xxxxxxxxxxxx"
```

### 3. Apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

A single apply creates:

- The `GrafanaCloudWatchAccessRole` in each spoke account, with a trust policy
  allowing Grafana Labs' AWS account (`008923505280`) to assume it — gated by a
  generated External ID.
- The `CloudWatch-<client-name>` data source in your Grafana Cloud stack for
  each spoke, using `authType = grafana_assume_role` with a **600 s minimum
  scrape interval**.

### 4. Verify

In Grafana Cloud, open **Connections → Data sources → CloudWatch-client-alpha**
and click **Save & test**. You should see `✓ Data source is working`.

## Multi-Account AWS Credentials

The spoke IAM role is created **inside each client account**. Terraform needs
credentials with IAM-write access there. Pick one strategy:

### Option A: `OrganizationAccountAccessRole` (AWS Organizations)

If the client accounts are members of your AWS Organization, assume
`OrganizationAccountAccessRole` from the management account. In `providers.tf`
replace the default AWS provider with aliases:

```hcl
provider "aws" {
  alias  = "client_alpha"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
  }
}
```

Then wire each module to its provider:

```hcl
module "spoke_client_alpha" {
  source    = "./modules/spoke"
  providers = { aws = aws.client_alpha }
  # ... other args
}
```

(The `for_each` version in `main.tf` needs to become per-client module blocks
because Terraform does not allow dynamic provider assignment.)

### Option B: Per-Account AWS CLI Profiles

Configure a named profile per client in `~/.aws/credentials`, then use provider
aliases pointing to each profile. Same structure as Option A but with `profile`
instead of `assume_role`.

### Option C: Separate Terraform Workspaces per Account

Deploy the spoke module independently per account — simplest for large fleets:

```bash
cd modules/spoke
AWS_PROFILE=client-alpha terraform init
AWS_PROFILE=client-alpha terraform apply \
  -var="external_id=$(terraform -chdir=../.. output -raw external_id)"
```

## Alternative: Python Provisioning Script

For existing spoke roles (managed outside Terraform), or to provision data
sources without Terraform state:

```bash
python scripts/provision_datasources.py \
  --stack-url "https://mycompany.grafana.net" \
  --sa-token "glsa_xxxxxxxxxxxx" \
  --region us-east-1 \
  --external-id "3f8b9d0e-1a2b-4c5d-9e6f-7a8b9c0d1e2f" \
  --spoke-accounts '{"client-alpha":"222222222222","client-bravo":"333333333333"}'
```

The script is idempotent — it creates or updates data sources by name.

## Billing Protection

**CRITICAL:** All CloudWatch data sources are configured with a **600-second
(10-minute) minimum scrape interval** (`timeInterval`). This prevents Grafana
dashboards from issuing aggressive `GetMetricData` API calls that would spike
client AWS bills.

Enforced in:

- `main.tf` — `grafana_data_source.cloudwatch` sets `timeInterval = "600s"`
- `scripts/provision_datasources.py` — `MIN_INTERVAL_SECONDS = 600`

> Do not lower this value without understanding the billing impact. CloudWatch
> `GetMetricData` is priced per 1,000 metrics returned; high-cardinality
> dashboards refreshing every 30 s can cost tens of dollars per day per client.

## Security Design

| Principle | Implementation |
|---|---|
| **Least privilege** | Spoke roles have only `CloudWatchReadOnlyAccess` (AWS managed) |
| **Explicit trust** | Spoke trust policy names the exact Grafana Labs AWS account |
| **Confused-deputy protection** | `sts:ExternalId` condition required on every assume-role call |
| **Stable external ID** | Generated once per stack, stored in state, reused across all spokes |
| **No wildcard resources** | Trust and data-source configs reference specific ARNs |
| **Secrets hygiene** | `.gitignore` excludes `terraform.tfvars`; SA token read from env |
| **Sensitive outputs** | `external_id` output marked sensitive in state |

### About the External ID

Grafana Cloud uses the External ID to prevent a "confused deputy" attack where
another Grafana Cloud tenant could try to assume your role. The same value must
appear in **both** places:

1. The spoke IAM role trust policy (`sts:ExternalId` condition)
2. The Grafana Cloud CloudWatch data source (`externalId` in JSON data)

Terraform wires these together automatically through the `local.external_id`
value. If you supply your own via `var.external_id`, use a high-entropy string
(UUID, 32+ random bytes). Never reuse it across stacks.

## Outputs

| Output | Description |
|---|---|
| `grafana_cloud_stack_url` | URL of the Grafana Cloud stack |
| `spoke_role_arns` | Map of spoke name → IAM role ARN |
| `external_id` | External ID used in trust policies (sensitive) |
| `data_source_names` | Data-source names provisioned in the stack |

## Adding a New Client Account

1. Add the account to `spoke_accounts` in `terraform.tfvars`:
   ```hcl
   spoke_accounts = {
     # existing accounts ...
     "client-delta" = "555555555555"
   }
   ```
2. Add a provider alias + module block for the new account (Option A/B) or run
   the spoke module in the new account (Option C).
3. `terraform apply` — a new spoke role and data source are created in a single
   pass, reusing the existing External ID.
