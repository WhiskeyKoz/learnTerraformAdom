<#
.SYNOPSIS
    One-command deploy (or destroy) of the Phase 1 stack: ECR -> image -> everything else.

.DESCRIPTION
    Runs the bootstrap order the stack needs, because ECS can't start tasks
    from an image that isn't in ECR yet:

      1. Preflight   - tools on PATH, Docker running, AWS credentials valid
      2. ECR only    - terraform apply -target=module.ecr
      3. Image       - build + push <repo>:<tag> (skipped if the tag already exists;
                       tags are immutable, so a re-push would fail anyway)
      4. Everything  - terraform apply (waits until the ECS tasks are healthy)
      5. Smoke test  - /health via the ALB, then requests grouped by AZ
      6. Drift check - terraform plan must report "No changes"

.PARAMETER ImageTag
    Image tag to build/deploy. Defaults to image_tag in terraform.tfvars.
    A different value is passed to Terraform with -var, so tfvars stays the
    default and this run deploys the given tag.

.PARAMETER AutoApprove
    Skip Terraform's "yes" prompts. Without it, every apply/destroy shows its
    plan and waits for you to confirm.

.PARAMETER Destroy
    Tear the whole stack down (terraform destroy) instead of deploying.

.EXAMPLE
    .\scripts\deploy.ps1                       # deploy, confirm each apply
    .\scripts\deploy.ps1 -AutoApprove          # deploy without prompts
    .\scripts\deploy.ps1 -ImageTag v1.0.1      # build/push/deploy a new version
    .\scripts\deploy.ps1 -Destroy              # tear everything down

    If scripts are blocked on this machine:
    powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$ImageTag,
    [switch]$AutoApprove,
    [switch]$Destroy
)

$ErrorActionPreference = 'Stop'

$Root         = Split-Path -Parent $PSScriptRoot
$TerraformDir = Join-Path $Root 'terraform'
$AppDir       = Join-Path $Root 'app\frontend'
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
if (-not $ImageTag) { $ImageTag = Get-TfVar 'image_tag' }
$tagArgs = @("-var=image_tag=$ImageTag")
Write-Ok "Region $region, image tag $ImageTag"

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
        Write-Ok 'Everything destroyed. The ECR image was deleted with the repository.'
        return
    }

    # Docker is only needed for deploy.
    if (-not (Test-NativeCommand { docker info })) {
        throw 'Docker is not running. Start Docker Desktop and try again.'
    }
    Write-Ok 'Docker running'

    # ----------------------------------------------------------------------
    # 2. ECR repository only
    # ----------------------------------------------------------------------
    Write-Step 'Step 1/5: Create the ECR repository (terraform apply -target=module.ecr)'
    # Quoted: PowerShell would otherwise split "-target=module.ecr" at the dot.
    terraform apply -input=false "-target=module.ecr" @tagArgs @approveArgs
    Assert-ExitCode 'terraform apply (ECR)'

    $repo = terraform output -raw ecr_repository_url
    Assert-ExitCode 'terraform output ecr_repository_url'
    $registry = $repo.Split('/')[0]
    $repoName = $repo.Split('/')[1]
    $image    = "${repo}:${ImageTag}"
    Write-Ok "Repository $repo"

    # ----------------------------------------------------------------------
    # 3. Build + push the image (skip if this tag is already in ECR)
    # ----------------------------------------------------------------------
    Write-Step "Step 2/5: Build and push $image"

    $tagExists = Test-NativeCommand {
        aws ecr describe-images --region $region --repository-name $repoName --image-ids "imageTag=$ImageTag"
    }

    if ($tagExists) {
        Write-Ok "Tag $ImageTag already in ECR - skipping build/push (tags are immutable; use -ImageTag for a new version)"
    }
    else {
        # Run the pipe in cmd: PowerShell 5.1 re-encodes piped text, which
        # corrupts the token and makes the login fail with 400 Bad Request.
        cmd /c "aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry"
        Assert-ExitCode 'docker login to ECR'

        # linux/amd64 = Fargate's default CPU architecture.
        # --provenance/--sbom=false = push one plain image manifest; otherwise
        # the real image is stored untagged and the ECR lifecycle rule
        # ("expire untagged after 1 day") would delete it.
        docker build --platform linux/amd64 --provenance=false --sbom=false -t $image $AppDir
        Assert-ExitCode 'docker build'

        docker push $image
        Assert-ExitCode 'docker push'
        Write-Ok "Pushed $image"
    }

    # ----------------------------------------------------------------------
    # 4. Everything else
    # ----------------------------------------------------------------------
    Write-Step 'Step 3/5: Deploy everything (terraform apply) - waits for healthy ECS tasks, ~4 min'
    terraform apply -input=false @tagArgs @approveArgs
    Assert-ExitCode 'terraform apply'

    $appUrl = terraform output -raw app_url
    Assert-ExitCode 'terraform output app_url'

    # ----------------------------------------------------------------------
    # 5. Smoke test through the ALB
    # ----------------------------------------------------------------------
    Write-Step "Step 4/5: Smoke test $appUrl"

    # A brand-new ALB's DNS name can take a minute to resolve.
    $healthy = $false
    for ($i = 1; $i -le 24 -and -not $healthy; $i++) {
        try {
            $r = Invoke-WebRequest "$appUrl/health" -UseBasicParsing -TimeoutSec 5
            $healthy = ($r.StatusCode -eq 200)
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
    if (-not $healthy) { throw "ALB did not answer $appUrl/health within 2 minutes." }
    Write-Ok '/health returned 200'

    $answers = 1..10 | ForEach-Object {
        (Invoke-WebRequest "$appUrl/api/whoami" -UseBasicParsing -TimeoutSec 5).Content | ConvertFrom-Json
    }
    $answers | Group-Object { $_.'Availability Zone' } | ForEach-Object {
        Write-Ok ("{0} requests -> {1}" -f $_.Count, $_.Name)
    }

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
    Write-Host 'Running cost is about $0.09/hour - tear down with: .\scripts\deploy.ps1 -Destroy' -ForegroundColor Yellow
}
finally {
    Pop-Location
}
