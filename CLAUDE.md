# AWS ECS Fargate IaC Demo (Terraform)

Hands-on Infrastructure as Code project showing how to design, automate and
secure a containerized AWS environment with Terraform.

## Target architecture (end state)

- **VPC A – Frontend / ingress:** public ALB + public-facing ECS Fargate service.
- **VPC B – Internal services:** private, isolated ECS Fargate backend/API with no internet access.
- **Inter-VPC:** VPC Peering with strict Security Group rules.

## Phase 1 (MVP) – ✅ COMPLETE (2026-10-13)

Single VPC: 2 public + 2 private subnets across 2 AZs, ALB in public subnets,
ECS Fargate service in private subnets, image in ECR, least-privilege IAM.
Deployed and verified end to end (40 resources), then destroyed to save cost.

## Phase 2 – 🚧 IN PROGRESS (branch `Phase2`, full plan in `phase2.txt`)

**Goal:** the user opens the **frontend** (VPC A, public ALB). The frontend calls the **backend API**
in a second, **isolated VPC B with no internet**, through an **internal ALB over VPC peering**. The page
shows info from both sides plus a **random quote** from the backend – proving traffic crossed the peering.

```
 Browser ──http──▶ Public ALB ──▶ FRONTEND (VPC A 10.10.0.0/16, AZ 1a+1b)
                                     │ GET /api/quote
                                     ▼  VPC Peering
                   Internal ALB ──▶ BACKEND API (VPC B 10.20.0.0/16, AZ 1a+1b, no internet)
```

**Core (building now):** backend API with random quotes from `app/backend/quotes.txt`; frontend shows
frontend box + backend box + quote, survives backend failure (2s timeout); VPC B private-only; peering
routes in private route tables only; second ECR repo / IAM role / log group / internal ALB / ECS service.

**Bonus (only when the user says so, after core is done):** B1 quotes + like counts in a DB
(DynamoDB or S3) · B2 👍 Like button → log line → metric filter → CloudWatch alarm (+ optional email)
· B3 edit a quote from the frontend (input + Save) and backend API (`PUT /api/quotes/<id>`).

**Open decisions:** Step 6 – security between the VPCs (network only vs. network + API key);
Bonus – DynamoDB vs. S3, email yes/no.

| Step | What | Status |
|---|---|---|
| 1 | Backend app (`app/backend`: API, `quotes.txt`, Dockerfile) | ✅ Done – tested locally in Docker |
| 2 | Frontend app update (backend call, quote box, graceful degradation) + `docker compose` | ⏳ Next |
| 3 | Make modules reusable (network w/o public subnets, internal ALB, flexible ECS) – Phase 1 plan must show no changes | ⬜ |
| 4 | VPC B + peering + routes | ⬜ |
| 5 | Backend layer (ECR, IAM, internal ALB, ECS) | ⬜ |
| 6 | Security groups between the VPCs (user decision) | ⬜ |
| 7 | `deploy.ps1` for 2 images | ⬜ |
| 8 | Full deploy + tests | ⬜ |

### Backend API (Phase 2 Step 1)

| Endpoint | Returns |
|---|---|
| `GET /api/quote` | `{"quote": {id, text, author}, "served_by": {Hostname, Private IP, Task ID, AZ, ...}}` – random each call |
| `GET /api/whoami` | Backend container info |
| `GET /health` | `{"status": "ok", "quotes_loaded": N}` (internal ALB health check) |
| anything else | `{"error": "not found"}`, 404 |

- `quotes.txt`: one quote per line `text | author`; `#` comments and blank lines ignored. Baked into the
  image (VPC B has no internet). Add a quote → new image tag → deploy.
- Quotes load **once at start-up**; a broken/missing file makes the container exit immediately
  (fail fast) instead of failing every request. `QUOTES_FILE` env var overrides the path.
- `served_by` in `/api/quote` lets the frontend fill the backend box from the **same** call.
- Same hardening as the frontend: non-root UID 10001, read-only root FS ready (`/dev/shm`), port 8080.

Local test (passed 2026-10-14, run with `--read-only --cap-drop ALL --security-opt no-new-privileges`):
```powershell
docker build --platform linux/amd64 --provenance=false --sbom=false -t adom-backend:local ./app/backend
docker run -d --name adom-backend-test --read-only --cap-drop ALL -p 8082:8080 adom-backend:local
curl.exe http://localhost:8082/api/quote      # random quote + served_by
curl.exe http://localhost:8082/health         # {"quotes_loaded":14,"status":"ok"}
docker rm -f adom-backend-test
```
Results: health OK (14 quotes), 30 calls → 11 different quotes, 404 JSON, runs as `appuser`,
writes blocked, missing quotes file → container exits with code 1.

## Progress

| Step | What | Status |
|---|---|---|
| 1 | App (Flask) + Dockerfile + Terraform root layout & `terraform.tfvars` | ✅ Done – tested locally in Docker |
| 2 | `network` module – VPC, subnets, IGW, route tables, VPC endpoints | ✅ Done – applied & verified |
| 3 | `ecr` module – image repository | ✅ Done – applied, image pushed & scanned |
| 4 | `iam` module + log group – task execution role + task role | ✅ Done – applied & verified |
| 5 | `alb` module – ALB, target group, listener, SG | ✅ Done – applied & verified |
| 6 | `ecs` module – cluster, task definition, service, SG | ✅ Done – applied & verified |
| 7 | Full deploy + end-to-end test (ALB URL, AZ alternation, logs, negative tests, drift) | ✅ Done – all passed (see "End-to-end results") |

## Quick start – deploy with one script

The file `scripts/deploy.ps1` does **all the deploy work for you**. You type **one** command
instead of about 10.

### Before you start

1. **Docker Desktop is running** (whale icon in the taskbar).
2. **AWS login works** – if not, run `aws configure`.
3. Open **PowerShell** and go to the project folder:
   ```powershell
   cd "C:\Users\navek\Nave files\adom terraform project\learnTerraformAdom"
   ```

### Deploy

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

Terraform stops **2 times** and asks `Enter a value:` – type **`yes`** and press Enter.
It takes about **6–8 minutes**. At the end it prints the **link to your app**.
Open it in the browser and type `http://` at the start (not `https://`).

### Delete everything when you finish (stops the cost, ~$0.09/hour)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -Destroy
```

Type **`yes`** when it asks.

### What the script does – in this order

```
 You type: .\scripts\deploy.ps1
              │
              ▼
 ① CHECK     Is Terraform installed? Docker running? AWS login OK?
              │   (if something is missing → it stops and tells you what)
              ▼
 ② ECR       terraform apply "-target=module.ecr"
              │   Creates ONLY the empty image storage (ECR). Nothing else.
              ▼
 ③ IMAGE     docker build + docker push
              │   Builds the app image and uploads it into ECR.
              │   (skipped if this image tag is already in ECR)
              ▼
 ④ DEPLOY    terraform apply
              │   Creates everything else: network, IAM, load balancer, containers.
              │   ECR already exists, so Terraform does not create it again.
              │   Waits until the 2 containers are healthy (~4 min).
              ▼
 ⑤ TEST      Opens the app 10 times → shows how many answers came from each AZ
              ▼
 ⑥ CHECK     terraform plan → must say "No changes" (code and AWS match)
              ▼
 ✅ Prints your link:  http://adom-demo-dev-alb-....amazonaws.com
```

### Why this order? (the most important part)

The containers need the image **before** they start. If you run one plain `terraform apply`,
Terraform creates everything at once – the containers start, but **ECR is still empty**, so they fail.

`-target=module.ecr` means: **"read all of `main.tf`, but create ONLY the ECR part."**

```
main.tf                      Step ② (-target)     Step ④ (normal apply)
 ├── module "network"         ⏸ skipped            ✅ created
 ├── module "ecr"             ✅ CREATED           ✔ already exists – no change
 ├── module "iam"             ⏸ skipped            ✅ created
 ├── module "alb"             ⏸ skipped            ✅ created
 └── module "ecs"             ⏸ skipped            ✅ created (image is already in ECR)
```

Like a restaurant: **first** build the fridge (ECR), **then** put the food inside (push the image),
**then** open the kitchen (ECS) – the cooks find food in the fridge right away.

### Options

| You type | What happens |
|---|---|
| `.\scripts\deploy.ps1` | Deploy. Asks you to type `yes` before creating things |
| `.\scripts\deploy.ps1 -AutoApprove` | Deploy without asking `yes` (needed when running from Claude Code with `!`) |
| `.\scripts\deploy.ps1 -Destroy` | Delete everything from AWS |
| `.\scripts\deploy.ps1 -ImageTag v1.0.1` | Build, upload and deploy a **new version** of the app (tags can't be reused) |
| `Get-Help .\scripts\deploy.ps1 -Full` | Show the built-in help |

(Add `powershell -ExecutionPolicy Bypass -File` in front if Windows blocks scripts.)

### If you get an error

| Message | What to do |
|---|---|
| `Docker is not running` | Open Docker Desktop, wait 1 minute, run again |
| `AWS credentials check failed` | Run `aws configure` |
| `running scripts is disabled on this system` | Use `powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1` |
| `'terraform' not found` | Install it: `winget install Hashicorp.Terraform`, then open a new PowerShell |
| Browser shows nothing / timeout | You opened `https://` – type `http://` at the start of the link |

The manual commands the script runs are in **"Deploy from scratch"** below (for learning / debugging).

## Project structure

```
.
├── CLAUDE.md
├── phase2.txt              # Phase 2 plan (core + bonus)
├── scripts/
│   └── deploy.ps1          # one-command deploy / destroy (see "Quick start")
├── tests/
│   └── egress-test.json    # one-off ECS task override: proves tasks cannot reach the internet
├── app/
│   ├── app.py              # Flask app: shows hostname, IP, ECS task ID & AZ (Phase 1 frontend;
│   ├── requirements.txt    #   moves to app/frontend/ in Phase 2 Step 2)
│   ├── Dockerfile
│   ├── .dockerignore
│   └── backend/            # Phase 2 backend API: app.py, quotes.txt, requirements.txt, Dockerfile
└── terraform/
    ├── providers.tf        # Terraform/provider version pins, default_tags, S3 backend (commented)
    ├── variables.tf        # typed + validated input variables
    ├── terraform.tfvars    # ALL environment-specific values (committed, no secrets)
    ├── main.tf             # root module – wires modules together + app CloudWatch log group
    ├── outputs.tf
    ├── .terraform.lock.hcl # provider version lock (committed)
    └── modules/            # each module: main.tf, variables.tf, outputs.tf
        ├── network/        # VPC, subnets, IGW, route tables, VPC endpoints, SGs
        ├── ecr/            # image repository + lifecycle policy
        ├── iam/            # ECS task execution role + task role
        ├── alb/            # public ALB, target group, HTTP listener, ALB SG
        └── ecs/            # cluster, task definition, service, tasks SG
```

## Request flow (Steps 5–6)

```
Internet ──80──▶ ALB (public subnets, 1a+1b) ──8080──▶ ECS tasks (private subnets, 1a+1b)
                 alb-sg: in 80 from alb_ingress_cidrs   tasks-sg: in 8080 ONLY from alb-sg
                         out 8080 ONLY to tasks-sg               out 443 ONLY to VPC endpoints + S3
                                                                        │
                                              ECR (image) · S3 (layers) · CloudWatch (logs)
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
(Phase 2 peering route goes here), `s3_prefix_list_id`, `vpc_endpoints_security_group_id`.

## Container registry (Step 3)

ECR repository `adom-demo-dev-app`: immutable tags, scan on push, AES256 encryption,
lifecycle policy (untagged expire after 1 day, keep newest 10).
Module outputs: `repository_name`, `repository_url`, `repository_arn`.

### Push the image (after apply)

```powershell
cd terraform
$REPO = terraform output -raw ecr_repository_url
$REGISTRY = $REPO.Split('/')[0]
# Pipe through cmd: PowerShell 5.1 re-encodes piped text and corrupts the token (-> 400 Bad Request)
cmd /c "aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin $REGISTRY"
docker build --platform linux/amd64 --provenance=false --sbom=false -t "${REPO}:v1.0.0" ../app
docker push "${REPO}:v1.0.0"
```

- `--platform linux/amd64`: Fargate's default CPU architecture.
- `--provenance=false --sbom=false` (**required**): otherwise Docker Desktop pushes an OCI *image index*
  whose real image manifest is **untagged** – the lifecycle rule "expire untagged after 1 day" would
  then delete the actual image and break `v1.0.0`, and ECR basic scanning doesn't scan indexes.
- Tags are immutable: bump `image_tag` in `terraform.tfvars` (e.g. `v1.0.1` or a git SHA) for every new build.
- `describe-images` scan summary can lag; use `aws ecr describe-image-scan-findings` for results.

## IAM (Step 4)

| Role | Used by | Permissions |
|---|---|---|
| `adom-demo-dev-ecs-execution-role` | ECS agent / Fargate | `ecr:GetAuthorizationToken` (`*`), pull from **this repo only**, create stream / put logs in **this log group only** |
| `adom-demo-dev-ecs-task-role` | App code in the container | **None** (app calls no AWS APIs) |

Both roles trust only `ecs-tasks.amazonaws.com`, conditioned on `aws:SourceAccount` + `aws:SourceArn`
(this account/region). Log group `/ecs/adom-demo-dev/app` (7-day retention) is created in the root module.

## ALB (Step 5)

Internet-facing ALB `adom-demo-dev-alb` in both public subnets; target group `adom-demo-dev-tg`
(`target_type = ip`, HTTP 8080, health check `/health` every 15s, healthy 2 / unhealthy 3,
deregistration delay 30s); HTTP 80 listener forwarding to it.
Module outputs: `alb_dns_name`, `alb_arn`, `alb_security_group_id`, `target_group_arn`.

## ECS (Step 6)

- Cluster `adom-demo-dev-cluster` (Container Insights toggle, off by default).
- Task definition `adom-demo-dev-app`: Fargate, `awsvpc`, X86_64, 0.25 vCPU / 512 MiB,
  read-only root FS, all Linux capabilities dropped, `awslogs` → `/ecs/adom-demo-dev/app` (stream `ecs/app/<task-id>`),
  env `APP_ENV`, `APP_NAME`.
- Service `adom-demo-dev-app`: 2 tasks in private subnets, no public IP, registered in the target group,
  rolling deploy 100%/200%, circuit breaker with rollback, `wait_for_steady_state = true`.
- Module outputs: `cluster_name`, `service_name`, `task_definition_arn`, `tasks_security_group_id`.
- Root outputs: `app_url`, `ecs_cluster_name`, `ecs_service_name`.

## Deploy from scratch (order matters) – manual commands

**Easy way:** `.\scripts\deploy.ps1` (see "Quick start"). These are the same steps by hand.

ECS can't run an image that isn't in ECR yet, and `wait_for_steady_state = true` makes `apply`
wait for healthy tasks – so a single `apply` from zero would hang and then fail. Use:

```powershell
cd terraform
terraform apply "-target=module.ecr" # 1. empty ECR repo only (quote it: PowerShell splits on the dot)
# 2. build + push the image (commands in "Push the image" above)
terraform apply                      # 3. everything else; waits until 2 tasks are healthy (~4 min)
terraform output app_url             # 4. open in browser - type http:// explicitly
terraform plan                       # 5. must say "No changes" (drift check)
terraform destroy                    # when done (~4 min)
```

**Browser tip:** Chrome/Edge may auto-upgrade to `https://`, which times out (no 443 listener).
Type the URL with `http://` explicitly.

Real-world: ECR in a separate long-lived "foundation" stack; CI/CD pushes a tag then applies with
`-var image_tag=...`. `-target` is only for this bootstrap, not routine use.

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
- `--worker-tmp-dir /dev/shm`: gunicorn heartbeat files go to tmpfs so the container runs with a
  read-only root filesystem. Tested locally: `docker run --read-only --cap-drop ALL --security-opt no-new-privileges`.

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

**IAM (Step 4)**
- **Two roles, separated:** execution role = ECS agent (pull image, ship logs); task role = app code.
  A compromised container only gets the task role's credentials – which have no permissions.
- **Custom policy instead of `AmazonECSTaskExecutionRolePolicy`:** the managed policy allows pulling
  from *any* repo and writing to *any* log group; ours is scoped to one repo ARN and one log group.
  Only `ecr:GetAuthorizationToken` uses `*` (AWS doesn't support resource-scoping it).
- **Confused-deputy protection:** trust policy conditions on `aws:SourceAccount` and `aws:SourceArn`.
- **Log group created by Terraform** (root module, shared by iam + ecs): fixed retention instead of
  never-expire, and no `logs:CreateLogGroup` needed at runtime.
- **Inline policy (`aws_iam_role_policy`)**: lifecycle tied to the role, can't be attached elsewhere.

**ALB + ECS (Steps 5–6)**
- **SG-to-SG references, not CIDRs:** tasks accept traffic only from the ALB's SG – nothing else in
  the VPC can reach them. The ALB SG's egress rule lives in the ecs module (it references the tasks SG).
- **Egress locked down too:** tasks may only reach the VPC endpoints SG and the S3 prefix list on 443 –
  a compromised app can't call the internet or move laterally. DNS and the task metadata endpoint are
  link-local and not filtered by SGs.
- **`target_type = "ip"`:** required for Fargate/`awsvpc` – each task has its own ENI + private IP.
- **Container hardening layers:** non-root image + read-only root FS + `capabilities.drop = ["ALL"]`.
- **Deployment safety:** rolling 100%/200% (no downtime), circuit breaker with auto-rollback,
  `wait_for_steady_state` so `apply` fails if tasks never become healthy.
- **`depends_on` on the `target_group_arn` output:** ECS rejects a service whose target group isn't
  attached to an ALB yet; exposing the ARN only after the listener exists enforces the order.
- **`drop_invalid_header_fields`:** ALB drops malformed headers (request-smuggling mitigation).
- **Short deregistration delay (30s)** instead of the 300s default → faster deployments.
- **HTTP only (demo):** HTTPS needs an ACM cert for an owned domain; prod = 443 listener + 80→443 redirect.
- **`alb_ingress_cidrs` in tfvars:** `0.0.0.0/0` for a public demo, or `<your-ip>/32` to lock it down.
- **Cost while running:** ALB + 2 × 0.25 vCPU tasks + endpoints ≈ $0.09/hr.
- **Explicit defaults in `container_definitions`** (`hostPort`, empty `mountPoints` / `volumesFrom` /
  `systemControls`, `capabilities.add = []`): AWS fills these in, so without them every `plan` showed
  a diff and would replace the task definition + redeploy the service (perpetual drift). Found by
  running `plan` right after `apply`.

## Testing strategy

| Level | What it proves |
|---|---|
| `terraform validate` / `plan` | Syntax, references, provider schema, variable validation, read access to AWS, intended changes |
| Apply + inspect (AWS CLI) | AWS accepts it: endpoints `available`, subnets/AZs, routes, SG rules |
| End-to-end (after Step 6) | Browser → ALB → private task; AZ alternates; image pull proves endpoints; logs in CloudWatch |
| Negative tests (after Step 6) | Tasks cannot reach the internet; tasks unreachable except via ALB |

`plan` does NOT catch quotas, IAM permission gaps, CIDR conflicts, or runtime behavior (DNS, pulls).

### Verification checklist (Steps 2–4, all passed on 2026-10-13)

| # | Check | Expected |
|---|---|---|
| 1 | VPC endpoints | `s3` Gateway + `ecr.api`, `ecr.dkr`, `logs` Interface in 2 subnets, private DNS on, all `available` |
| 2 | Subnets | public + private in each of 1a/1b, correct CIDRs, `MapPublicIpOnLaunch = False` |
| 3 | Route tables | public: `0.0.0.0/0 -> igw`; private: `local` + S3 prefix list only (**no** `0.0.0.0/0`) |
| 4 | Security groups | vpce-sg: tcp/443 from `10.10.11.0/24` + `10.10.12.0/24`, no egress; default SG: no rules |
| 5 | ECR | `v1.0.0` is a single image manifest, scan `COMPLETE` |
| 6 | IAM simulation (execution role) | pull **our** repo: allowed; other repo / `ecr:PutImage` / `s3:GetObject`: denied |
| 7 | Task role | 0 inline + 0 attached policies |
| 8 | Log group | `/ecs/adom-demo-dev/app`, retention 7 days |

Note: the IAM policy simulator cannot evaluate `logs:PutLogEvents` against log-stream ARNs (it returns
`implicitDeny` even for `Resource: "*"`). Log write permission was proven end-to-end in Step 7
(container logs appeared in CloudWatch).

### End-to-end results (Step 7, all passed on 2026-10-13)

| # | Test | Result |
|---|---|---|
| 1 | Bootstrap order (ECR → push → apply) | 40 resources; service steady/healthy 67s after creation |
| 2 | ALB `/health` + `/` | `{"status":"ok"}`, HTTP 200 |
| 3 | Multi-AZ load balancing (20 requests) | 10 → `eu-central-1a` (10.10.11.246), 10 → `eu-central-1b` (10.10.12.81) |
| 4 | Target group health | both targets `healthy` |
| 5 | ECS service | running 2/2, rollout `COMPLETED` |
| 6 | Task ENIs | no public IP on either task |
| 7 | CloudWatch logs | one stream per task; gunicorn + `ELB-HealthChecker` lines (from ALB node in public subnet) |
| 8 | Image pull via endpoints | tasks started with no internet route → ECR/S3 endpoints work |
| 9 | **Negative:** task → internet | `example.com`, `google.com`: BLOCKED ("Network is unreachable") |
| 10 | Positive control: task → ECR | `api.ecr...` resolves to private IP `10.10.12.239` (endpoint DNS), REACHABLE |
| 11 | Drift check (`plan` after `apply`) | initially found perpetual task-def diff → fixed → "No changes" |
| 12 | `alb_ingress_cidrs` change | switching to `<ip>/32` and back replaced only the one SG rule |

**How the negative test works – one-off task with a command override** (same task def, subnets, SG
as the service; prints results to CloudWatch, then exits):

```bash
aws ecs run-task --cluster adom-demo-dev-cluster --task-definition adom-demo-dev-app --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<private-subnet-ids>],securityGroups=[<tasks-sg>],assignPublicIp=DISABLED}" \
  --overrides file://tests/egress-test.json   # python script trying internet + ECR URLs
aws ecs wait tasks-stopped --cluster adom-demo-dev-cluster --tasks <task-arn>
aws logs get-log-events --log-group-name /ecs/adom-demo-dev/app --log-stream-name ecs/app/<task-id>
```

**Console checks (eu-central-1):** VPC → Resource map; Route tables → private RT has no `0.0.0.0/0`;
Endpoints → 4 Available; ECR → image + scan findings; IAM → roles; CloudWatch → Log groups.

**CLI:**
```powershell
cd terraform
terraform output
terraform plan   # "No changes" = no drift between code and AWS
aws ec2 describe-vpc-endpoints --region eu-central-1 --filters Name=tag:Project,Values=adom-demo --query "VpcEndpoints[].[ServiceName,State]" --output table
aws ecr describe-image-scan-findings --region eu-central-1 --repository-name adom-demo-dev-app --image-id imageTag=v1.0.0 --query "imageScanFindings.findingSeverityCounts"
aws iam simulate-principal-policy --policy-source-arn <execution-role-arn> --action-names ecr:BatchGetImage --resource-arns <repo-arn>
```

## Known issues / follow-ups

- **Base image CVEs:** scan of `python:3.12-slim` found 3 HIGH (zlib CVE-2026-85091, glibc
  CVE-2026-5435, CVE-2026-19499), 9 MEDIUM, 3 LOW – all in OS packages, not app code. Fix by
  rebuilding once Debian ships patches, or add `apt-get upgrade` in the Dockerfile.
- **Environment is currently destroyed** (cost saving). Recreate with `.\scripts\deploy.ps1`
  (`ecr_force_delete = true` deleted the image with the repo; the script pushes it again).
- **`scripts/deploy.ps1` deploy path not yet run end to end** – only its `-Destroy` path (on empty
  state) and helper functions were tested. Parse check passed on Windows PowerShell 5.1.
- **HTTPS:** HTTP-only for the demo. Production: ACM certificate + 443 listener + 80→443 redirect.
- **Possible hardening later:** ALB access logs to S3, VPC Flow Logs, WAF on the ALB, ECS Exec
  (needs `ssmmessages` endpoint + task role permissions), remote state backend (S3 + lockfile).
- Old ECS task definition revisions stay as `INACTIVE` after destroy (no cost).

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
| `log_retention_days` | `7` |
| `alb_ingress_cidrs` | `["0.0.0.0/0"]` (public demo) |
| `enable_container_insights` | `false` |
| `container_port` | `8080` |
| `image_tag` | `v1.0.0` (immutable – bump per build) |
| `task_cpu` / `task_memory` | `256` / `512` |
| `desired_count` | `2` (one task per AZ) |

## Working conventions

- Build step by step; explain each architectural decision (interview prep).
- Before moving to the next step, ask whether to update this file; only update it when told to.
- On this Windows machine Docker and Terraform are on the PowerShell PATH, not Git Bash – run them via PowerShell.
- In a fresh PowerShell, refresh PATH first if `terraform` isn't found:
  `$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")`
- Prerequisites: Docker Desktop, Terraform >= 1.6 (`winget install Hashicorp.Terraform`), AWS CLI with credentials.
- Never `terraform apply`/`destroy` without explicit approval – it creates real, billable resources.
- After every `apply`, run `terraform plan` and expect "No changes" (catches perpetual drift).
- PowerShell: quote args containing dots, e.g. `terraform apply "-target=module.ecr"`.

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
