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
| 2 | `network` module – VPC, subnets, IGW, route tables, VPC endpoints | ⏳ Next |
| 3 | `ecr` module – image repository | ⬜ |
| 4 | `iam` module – task execution role + task role | ⬜ |
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
    └── modules/            # network, ecr, iam, alb, ecs (added step by step)
```

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

**Planned (Step 2)**
- Private-subnet tasks reach ECR/CloudWatch through **VPC endpoints** (ECR api/dkr, S3 gateway, Logs)
  rather than a NAT Gateway: no internet route at all, and the same pattern VPC B needs in Phase 2.

## Configuration (`terraform/terraform.tfvars`)

| Variable | Value |
|---|---|
| `aws_region` | `eu-central-1` |
| `project_name` / `environment` | `adom-demo` / `dev` |
| `vpc_cidr` | `10.10.0.0/16` |
| `availability_zones` | `eu-central-1a`, `eu-central-1b` |
| `public_subnet_cidrs` | `10.10.1.0/24`, `10.10.2.0/24` |
| `private_subnet_cidrs` | `10.10.11.0/24`, `10.10.12.0/24` |
| `container_port` | `8080` |
| `task_cpu` / `task_memory` | `256` / `512` |
| `desired_count` | `2` (one task per AZ) |

## Working conventions

- Build step by step; explain each architectural decision (interview prep).
- Before moving to the next step, ask whether to update this file; only update it when told to.
- On this Windows machine Docker is on the PowerShell PATH, not Git Bash – run Docker via PowerShell.
- Prerequisites: Docker Desktop, Terraform >= 1.6 (`winget install Hashicorp.Terraform`), AWS CLI with credentials.
