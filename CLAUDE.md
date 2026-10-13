# AWS ECS Fargate IaC Demo (Terraform)

Hands-on Infrastructure as Code project showing how to design, automate and
secure a containerized AWS environment with Terraform.

## Target architecture (end state)

- **VPC A – Frontend / ingress:** public ALB + public-facing ECS Fargate service.
- **VPC B – Internal services:** private, isolated ECS Fargate backend/API with no internet access.
- **Inter-VPC:** VPC Peering with strict Security Group rules.

## Current scope: Phase 1 (MVP)

Single VPC: 2 public + 2 private subnets across 2 AZs, ALB in public subnets,
ECS Fargate service in private subnets, image in ECR, least-privilege IAM.
**Phase 2 (multi-VPC / peering) is out of scope until Phase 1 is complete.**

## Progress

| Step | What | Status |
|---|---|---|
| 1 | App (Flask) + Dockerfile + Terraform root layout & `terraform.tfvars` | ✅ Done – tested locally in Docker |
| 2 | `network` module – VPC, subnets, IGW, route tables, VPC endpoints | ✅ Done – `validate` + `plan` clean (21 to add); not yet applied |
| 3 | `ecr` module – image repository | ✅ Done – `validate` + `plan` clean (23 to add total); not yet applied |
| 4 | `iam` module – task execution role + task role | ⏳ Next |
| 5 | `alb` module – ALB, target group, listener, SG | ⬜ |
| 6 | `ecs` module – cluster, task definition, service, SG | ⬜ |

## Project structure

```
.
├── CLAUDE.md
├── app/
│   ├── app.py              # Flask app: shows hostname, IP, ECS task ID & AZ
│   ├── requirements.txt    # flask, gunicorn (pinned)
│   ├── Dockerfile
│   └── .dockerignore
└── terraform/
    ├── providers.tf        # Terraform/provider version pins, default_tags, S3 backend (commented)
    ├── variables.tf        # typed + validated input variables
    ├── terraform.tfvars    # ALL environment-specific values (committed, no secrets)
    ├── main.tf             # root module – wires child modules together
    ├── outputs.tf
    ├── .terraform.lock.hcl # provider version lock (committed)
    └── modules/            # each module: main.tf, variables.tf, outputs.tf
        ├── network/        # VPC, subnets, IGW, route tables, VPC endpoints, SGs
        └── ecr/            # image repository + lifecycle policy
        # iam, alb, ecs added in later steps
```

## Network layout (Step 2)

```
VPC 10.10.0.0/16  (DNS support + hostnames on)
├── IGW
├── eu-central-1a: public 10.10.1.0/24  | private 10.10.11.0/24
├── eu-central-1b: public 10.10.2.0/24  | private 10.10.12.0/24
├── public-rt  : 0.0.0.0/0 -> IGW         (public subnets)
├── private-rt : local + S3 endpoint only  (private subnets - no internet route)
├── VPC endpoints: s3 (Gateway), ecr.api, ecr.dkr, logs (Interface, both AZs)
├── vpce-sg    : 443 in from private subnet CIDRs only
└── default SG locked down (no rules)
```

Module outputs: `vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`private_subnet_cidrs`, `public_route_table_id`, `private_route_table_id`
(Phase 2 peering route goes here), `vpc_endpoints_security_group_id`.

## Container registry (Step 3)

ECR repository `adom-demo-dev-app`: immutable tags, scan on push, AES256 encryption,
lifecycle policy (untagged expire after 1 day, keep newest 10).
Module outputs: `repository_name`, `repository_url`, `repository_arn`.

### Push the image (after apply)

```powershell
cd terraform
$REPO = terraform output -raw ecr_repository_url
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin $REPO.Split('/')[0]
docker build -t "${REPO}:v1.0.0" ../app
docker push "${REPO}:v1.0.0"
```

Tags are immutable: bump `image_tag` in `terraform.tfvars` (e.g. `v1.0.1` or a git SHA) for every new build.

## The app

| Endpoint | Purpose |
|---|---|
| `/` | HTML page: hostname, private IP, and on ECS also Task ID, AZ, cluster |
| `/api/whoami` | Same info as JSON |
| `/health` | ALB target group health check, dependency-free |

ECS details come from the Task Metadata Endpoint v4 (`ECS_CONTAINER_METADATA_URI_V4`).
Locally they are omitted and `Environment` shows `local`.

### Run locally

```powershell
docker build -t adom-demo:local ./app
docker run -d --name adom-demo-test -p 8080:8080 -e APP_NAME="Adom Demo" adom-demo:local
# open http://localhost:8080
docker rm -f adom-demo-test
```

## Key architectural decisions

**App / container**
- AZ + task ID on the page: refreshing behind the ALB visibly proves multi-AZ load balancing.
- Separate `/health` endpoint so health checks never depend on page rendering.
- `python:3.12-slim`: small image, smaller attack surface, faster pulls into Fargate.
- Dependencies copied before code for Docker layer caching.
- Runs as non-root `appuser` (UID 10001) → port 8080, since non-root can't bind < 1024.
- Gunicorn (production WSGI) instead of Flask dev server; logs to stdout → CloudWatch via `awslogs`.

**Terraform**
- All configuration lives in `terraform.tfvars`; `variables.tf` validates input so bad values fail at `plan`.
- `default_tags` on the provider tags every resource (Project / Environment / ManagedBy).
- Naming convention: `<project>-<env>-<resource>` via `local.name_prefix`.
- VPC CIDR `10.10.0.0/16`; Phase 2 VPC B must NOT overlap (e.g. `10.20.0.0/16`) or peering is impossible.
- Network is a reusable module so Phase 2 can instantiate it twice instead of copying code.
- `terraform.tfvars` and `.terraform.lock.hcl` are committed; state files are git-ignored.
  Secrets never go in tfvars (use SSM Parameter Store / Secrets Manager).

- AWS provider pinned to `~> 6.0` (lock file currently resolves v6.68.0); Terraform `>= 1.6`.

**Network (Step 2)**
- **VPC endpoints instead of NAT Gateway:** private subnets have no internet route at all; tasks
  reach ECR/CloudWatch via endpoints. Smaller attack surface, no exfiltration path, and the same
  pattern VPC B needs in Phase 2.
- **S3 Gateway endpoint** (free) is required because ECR stores image layers in S3. Its policy
  allows only `s3:GetObject` on ECR's layer bucket (`prod-<region>-starport-layer-bucket`).
- **Endpoint SG** allows only HTTPS 443 from the private subnet CIDRs; uses the newer
  `aws_vpc_security_group_ingress_rule` resource (one rule per subnet) instead of inline rules.
- **Default SG locked down** (CIS benchmark): resources launched without an explicit SG get no access.
- **`for_each` keyed by AZ name, not `count`:** adding/removing an AZ doesn't shift indexes and
  force-recreate the other subnets.
- **Single private route table:** with no NAT there's no per-AZ next hop, so one table suffices.
- **`map_public_ip_on_launch = false`** everywhere; the ALB gets public IPs regardless.
- **Cost:** 3 Interface endpoints × 2 AZs ≈ $0.06/hr (~$44/month). `terraform destroy` when not demoing.

**Container registry (Step 3)**
- **Immutable tags:** a tag always maps to the same image digest → reproducible deploys and exact
  rollbacks; a running tag can't be silently overwritten (supply-chain safety). `image_tag`
  validation rejects `"latest"`.
- **Scan on push:** free basic CVE scan of OS packages on every push.
- **AES256 encryption at rest** (AWS-managed, free); move to KMS for custom key policy / key-usage audit.
- **Lifecycle policy:** bounded storage cost without manual cleanup.
- **`force_delete` driven by tfvars:** `true` in dev so `destroy` works with images present; `false` for prod.
- **No repository policy:** access via IAM; Step 4's execution role is scoped to this repo's ARN.

## Testing strategy

| Level | What it proves |
|---|---|
| `terraform validate` / `plan` | Syntax, references, provider schema, variable validation, read access to AWS, intended changes |
| Apply + inspect (AWS CLI) | AWS accepts it: endpoints `available`, subnets/AZs, routes, SG rules |
| End-to-end (after Step 6) | Browser → ALB → private task; AZ alternates; image pull proves endpoints; logs in CloudWatch |
| Negative tests (after Step 6) | Tasks cannot reach the internet; tasks unreachable except via ALB |

`plan` does NOT catch quotas, IAM permission gaps, CIDR conflicts, or runtime behavior (DNS, pulls).

## Configuration (`terraform/terraform.tfvars`)

| Variable | Value |
|---|---|
| `aws_region` | `eu-central-1` |
| `project_name` / `environment` | `adom-demo` / `dev` |
| `vpc_cidr` | `10.10.0.0/16` |
| `availability_zones` | `eu-central-1a`, `eu-central-1b` |
| `public_subnet_cidrs` | `10.10.1.0/24`, `10.10.2.0/24` |
| `private_subnet_cidrs` | `10.10.11.0/24`, `10.10.12.0/24` |
| `ecr_force_delete` / `ecr_max_image_count` | `true` / `10` |
| `container_port` | `8080` |
| `image_tag` | `v1.0.0` (immutable – bump per build) |
| `task_cpu` / `task_memory` | `256` / `512` |
| `desired_count` | `2` (one task per AZ) |

## Working conventions

- Build step by step; explain each architectural decision (interview prep).
- Before moving to the next step, ask whether to update this file; only update it when told to.
- On this Windows machine Docker and Terraform are on the PowerShell PATH, not Git Bash – run them via PowerShell.
- Prerequisites: Docker Desktop, Terraform >= 1.6 (`winget install Hashicorp.Terraform`), AWS CLI with credentials.
- Never `terraform apply`/`destroy` without explicit approval – it creates real, billable resources.

## Common commands

```powershell
cd terraform
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply      # only with approval
terraform destroy    # tear down when not demoing
```
