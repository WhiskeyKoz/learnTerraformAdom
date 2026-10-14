<#
.SYNOPSIS
    One-command deploy (or destroy) of the Phase 2 stack: 2 ECR repos -> 2 images -> everything else.

.DESCRIPTION
    Runs the bootstrap order the stack needs, because ECS can't start tasks
    from an image that isn't in ECR yet:

      1. Preflight   - tools on PATH, Docker running, AWS credentials valid
      2. ECR only    - terraform apply -target=module.ecr_frontend -target=module.ecr_backend
      3. Images      - build + push the frontend AND the backend image
                       (each skipped if its tag already exists; tags are
                       immutable, so a re-push would fail anyway)
      4. Everything  - terraform apply (waits until both ECS services are healthy)
      5. Smoke test  - frontend /health via the public ALB, then /api/status 10x:
                       backend answered every time (= traffic crossed the peering),
                       AZs of frontend and backend; backend URL NOT reachable from here
      6. Drift check - terraform plan must report "No changes"

.PARAMETER FrontendTag
    Frontend image tag to build/deploy. Defaults to frontend_image_tag in terraform.tfvars.
    A different value is passed to Terraform with -var, so tfvars stays the
    default and this run deploys the given tag.

.PARAMETER BackendTag
    Backend image tag to build/deploy. Defaults to backend_image_tag in terraform.tfvars.

.PARAMETER AutoApprove
    Skip Terraform's "yes" prompts. Without it, every apply/destroy shows its
    plan and waits for you to confirm.

.PARAMETER Destroy
    Tear the whole stack down (terraform destroy) instead of deploying.

.EXAMPLE
    .\scripts\deploy.ps1                          # deploy, confirm each apply
    .\scripts\deploy.ps1 -AutoApprove             # deploy without prompts
    .\scripts\deploy.ps1 -BackendTag v1.0.1       # new backend version (e.g. after editing quotes.txt)
    .\scripts\deploy.ps1 -FrontendTag v1.0.1      # new frontend version
    .\scripts\deploy.ps1 -Destroy                 # tear everything down

    If scripts are blocked on this machine:
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$FrontendTag,
    [string]$BackendTag,
    [switch]$AutoApprove,
    [switch]$Destroy
)

$ErrorActionPreference = 'Stop'

$Root         = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $Root 'terraform'
$TfVarsFile   = Join-Path $TerraformDir 'terraform.tfvars'

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "    OK  $Text" -ForegroundColor Green
}

# Native commands (terraform, docker, aws) don't throw on failure - check the
# exit code after each one and stop the script if it failed.
function Assert-ExitCode([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed (exit code $LASTEXITCODE)."
    }
}

# Run a native command silently and return $true if it succeeded. Windows
# PowerShell 5.1 turns redirected stderr into a terminating error when
# $ErrorActionPreference is 'Stop', so relax it for the duration of the call.
function Test-NativeCommand([scriptblock]$Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Command *> $null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Get-TfVar([string]$Name) {
    $line = Select-String -Path $TfVarsFile -Pattern "^\s*$Name\s*=\s*`"([^`"]+)`"" | Select-Object -First 1
    if (-not $line) { throw "Could not find $Name in $TfVarsFile." }
    return $line.Matches[0].Groups[1].Value
}

# Build + push one image to its ECR repo. Skipped if the tag is already there.
function Publish-Image([string]$Name, [string]$Repo, [string]$Tag, [string]$AppDir) {
    $registry = $Repo.Split('/')[0]
    $repoName = $Repo.Split('/')[1]
    $image    = "${Repo}:${Tag}"

    $tagExists = Test-NativeCommand {
        aws ecr describe-images --region $region --repository-name $repoName --image-ids "imageTag=$Tag"
    }
    if ($tagExists) {
        Write-Ok "$Name tag $Tag already in ECR - skipping build/push (tags are immutable; use -${Name}Tag for a new version)"
        return
    }

    # Run the pipe in cmd: PowerShell 5.1 re-encodes piped text, which
    # corrupts the token and makes the login fail with 400 Bad Request.
    cmd /c "aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry"
    Assert-ExitCode 'docker login to ECR'

    # linux/amd64 = Fargate's default CPU architecture.
    # --provenance/--sbom=false = push one plain image manifest; otherwise
    # the real image is stored untagged and the ECR lifecycle rule
    # ("expire untagged after 1 day") would delete it.
    docker build --platform linux/amd64 --provenance=false --sbom=false -t $image $AppDir
    Assert-ExitCode "docker build ($Name)"

    docker push $image
    Assert-ExitCode "docker push ($Name)"
    Write-Ok "Pushed $image"
}

# Smoke test of the running stack, through the public ALB only:
#   - frontend /health
#   - /api/status 10x: the frontend calls the backend (VPC A -> peering -> VPC B)
#   - the backend URL must NOT be reachable from this PC
# Throws on any failure. $Retries x 5 s = how long to wait for new ALBs.
function Invoke-SmokeTest([string]$AppUrl, [string]$BackendUrl, [int]$Retries = 24) {
    # A brand-new ALB's DNS name can take a minute to resolve.
    $healthy = $false
    for ($i = 1; $i -le $Retries -and -not $healthy; $i++) {
        try {
            $r = Invoke-WebRequest "$AppUrl/health" -UseBasicParsing -TimeoutSec 5
            $healthy = ($r.StatusCode -eq 200)
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    if (-not $healthy) { throw "Public ALB did not answer $AppUrl/health after $Retries tries." }
    Write-Ok 'Frontend /health returned 200'

    # /api/status = the frontend calls the backend (VPC A -> peering -> VPC B).
    # Wait until the first backend call works (internal ALB DNS can lag too).
    $backendOk = $false
    for ($i = 1; $i -le $Retries -and -not $backendOk; $i++) {
        try {
            $s = (Invoke-WebRequest "$AppUrl/api/status" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
            $backendOk = [bool]$s.backend.ok
        }
        catch { }
        if (-not $backendOk) { Start-Sleep -Seconds 5 }
    }
    if (-not $backendOk) { throw "Frontend could not reach the backend after $Retries tries: $($s.backend.error)" }

    $answers = 1..10 | ForEach-Object {
        (Invoke-WebRequest "$AppUrl/api/status" -UseBasicParsing -TimeoutSec 10).Content | ConvertFrom-Json
    }
    $failed = @($answers | Where-Object { -not $_.backend.ok }).Count
    if ($failed -gt 0) { throw "$failed of 10 backend calls failed." }
    Write-Ok '10 of 10 backend calls OK (frontend -> peering -> internal ALB -> backend)'
    $answers | Group-Object { $_.frontend.'Availability Zone' } | ForEach-Object {
        Write-Ok ("frontend: {0} requests -> {1}" -f $_.Count, $(if ($_.Name) { $_.Name } else { "unknown AZ" }))
    }
    $answers | Group-Object { $_.backend.data.served_by.'Availability Zone' } | ForEach-Object {
        Write-Ok ("backend:  {0} requests -> {1}" -f $_.Count, $(if ($_.Name) { $_.Name } else { "unknown AZ" }))
    }
    $quotes = @($answers | ForEach-Object { $_.backend.data.quote.id } | Sort-Object -Unique).Count
    Write-Ok "$quotes different quotes in 10 calls"

    # Negative check: the internal ALB has private IPs only - this PC can't reach it.
    $reachable = $true
    try { Invoke-WebRequest "$BackendUrl/health" -UseBasicParsing -TimeoutSec 5 | Out-Null }
    catch { $reachable = $false }
    if ($reachable) { throw "Backend $BackendUrl answered from the internet - it must be private!" }
    Write-Ok 'Backend NOT reachable from this PC (internal ALB, private IPs only)'
}

$approveArgs = @()
if ($AutoApprove) { $approveArgs = @('-auto-approve') }

# --------------------------------------------------------------------------
# 1. Preflight
# --------------------------------------------------------------------------
Write-Step 'Preflight checks'

# Tools installed by winget aren't on PATH in an already-open window.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

foreach ($tool in 'terraform', 'aws', 'docker') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' not found on PATH. Install it first (see CLAUDE.md > Prerequisites)."
    }
}
Write-Ok 'terraform, aws, docker found'

$account = aws sts get-caller-identity --query Account --output text
Assert-ExitCode 'AWS credentials check (run "aws configure")'
Write-Ok "AWS account $account"

$region = Get-TfVar 'aws_region'
if (-not $FrontendTag) { $FrontendTag = Get-TfVar 'frontend_image_tag' }
if (-not $BackendTag)  { $BackendTag  = Get-TfVar 'backend_image_tag' }
$tagArgs = @("-var=frontend_image_tag=$FrontendTag", "-var=backend_image_tag=$BackendTag")
Write-Ok "Region $region, frontend tag $FrontendTag, backend tag $BackendTag"

Push-Location $TerraformDir
try {
    terraform init -input=false | Out-Null
    Assert-ExitCode 'terraform init'
    Write-Ok 'terraform init'

    # ----------------------------------------------------------------------
    # Destroy mode
    # ----------------------------------------------------------------------
    if ($Destroy) {
        Write-Step 'Destroying the whole stack'
        terraform destroy -input=false @tagArgs @approveArgs
        Assert-ExitCode 'terraform destroy'
        Write-Ok 'Everything destroyed. The ECR images were deleted with the repositories.'
        return
    }

    # Docker is only needed for deploy.
    if (-not (Test-NativeCommand { docker info })) {
        throw 'Docker is not running. Start Docker Desktop and try again.'
    }
    Write-Ok 'Docker running'

    # ----------------------------------------------------------------------
    # 2. ECR repositories only
    # ----------------------------------------------------------------------
    Write-Step 'Step 1/5: Create the 2 ECR repositories (terraform apply -target=...)'
    # Quoted: PowerShell would otherwise split "-target=module.ecr_..." at the dot.
    terraform apply -input=false "-target=module.ecr_frontend" "-target=module.ecr_backend" @tagArgs @approveArgs
    Assert-ExitCode 'terraform apply (ECR)'

    $frontendRepo = terraform output -raw frontend_ecr_repository_url
    Assert-ExitCode 'terraform output frontend_ecr_repository_url'
    $backendRepo = terraform output -raw backend_ecr_repository_url
    Assert-ExitCode 'terraform output backend_ecr_repository_url'
    Write-Ok "Repositories $frontendRepo, $backendRepo"

    # ----------------------------------------------------------------------
    # 3. Build + push both images
    # ----------------------------------------------------------------------
    Write-Step 'Step 2/5: Build and push the frontend and backend images'
    Publish-Image -Name 'Frontend' -Repo $frontendRepo -Tag $FrontendTag -AppDir (Join-Path $Root 'app\frontend')
    Publish-Image -Name 'Backend'  -Repo $backendRepo  -Tag $BackendTag  -AppDir (Join-Path $Root 'app\backend')

    # ----------------------------------------------------------------------
    # 4. Everything else
    # ----------------------------------------------------------------------
    Write-Step 'Step 3/5: Deploy everything (terraform apply) - waits for both ECS services to be healthy, ~6 min'
    terraform apply -input=false @tagArgs @approveArgs
    Assert-ExitCode 'terraform apply'

    $appUrl = terraform output -raw app_url
    Assert-ExitCode 'terraform output app_url'
    $backendUrl = terraform output -raw backend_url
    Assert-ExitCode 'terraform output backend_url'

    # ----------------------------------------------------------------------
    # 5. Smoke test through the public ALB
    # ----------------------------------------------------------------------
    Write-Step "Step 4/5: Smoke test $appUrl"

    Invoke-SmokeTest -AppUrl $appUrl -BackendUrl $backendUrl

    # ----------------------------------------------------------------------
    # 6. Drift check
    # ----------------------------------------------------------------------
    Write-Step 'Step 5/5: Drift check (terraform plan should show no changes)'
    terraform plan -input=false -detailed-exitcode @tagArgs | Out-Null
    switch ($LASTEXITCODE) {
        0       { Write-Ok 'No changes - code and AWS match' }
        2       { Write-Host '    WARN  terraform plan shows changes right after apply - run "terraform plan" to see them' -ForegroundColor Yellow }
        default { throw 'terraform plan (drift check) failed.' }
    }

    Write-Host ''
    Write-Host "Deployed. Open in your browser (type http:// explicitly): $appUrl" -ForegroundColor Green
    Write-Host 'Running cost is about $0.19/hour - tear down with: .\scripts\deploy.ps1 -Destroy' -ForegroundColor Yellow
}
finally {
    Pop-Location
}
