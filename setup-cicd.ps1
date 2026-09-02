# Charitize GitHub Actions OIDC CI/CD setup
# Reuses the existing AWS resources. It does NOT create/delete an Elastic Beanstalk environment.

$ErrorActionPreference = "Stop"

$AccountId = "299332719369"
$Region = "us-east-1"
$Owner = "Uchendu130617"
$Repo = "my-env-charitize"
$Branch = "main"
$Application = "charitize"
$Environment = "my-env"
$RoleName = "GitHubActions-Charitize-EB"
$PolicyName = "CharitizeGitHubEBDeployPolicy"
$ProviderArn = "arn:aws:iam::299332719369:oidc-provider/token.actions.githubusercontent.com"
$RoleArn = "arn:aws:iam::299332719369:role/GitHubActions-Charitize-EB"
$PolicyArn = "arn:aws:iam::299332719369:policy/CharitizeGitHubEBDeployPolicy"

function Require-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed or is not in PATH."
    }
}

Write-Host "=== Charitize OIDC CI/CD setup ===" -ForegroundColor Cyan
Require-Command aws
Require-Command gh

aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) { throw "AWS CLI authentication failed." }

gh auth status
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI authentication failed." }

Write-Host "`n[1/7] Reading GitHub repository..." -ForegroundColor Yellow
$repoInfo = gh api "repos/$Owner/$Repo" | ConvertFrom-Json
$repoId = [string]$repoInfo.id
$ownerId = [string]$repoInfo.owner.id

$oidcConfig = gh api "repos/$Owner/$Repo/actions/oidc/customization/sub" | ConvertFrom-Json

if ($oidcConfig.use_immutable_subject -eq $true) {
    $sub = "repo:$Owner@$ownerId/$Repo@$repoId`:ref:refs/heads/$Branch"
} else {
    $sub = "repo:$Owner/$Repo`:ref:refs/heads/$Branch"
}

Write-Host "Repository: $Owner/$Repo"
Write-Host "OIDC immutable subject: $($oidcConfig.use_immutable_subject)"
Write-Host "Required GitHub sub: $sub" -ForegroundColor Green

Write-Host "`n[2/7] Checking OIDC provider..." -ForegroundColor Yellow
$providers = aws iam list-open-id-connect-providers | ConvertFrom-Json
$exists = $providers.OpenIDConnectProviderList | Where-Object { $_.Arn -eq $ProviderArn }

if (-not $exists) {
    aws iam create-open-id-connect-provider `
        --url "https://token.actions.githubusercontent.com" `
        --client-id-list "sts.amazonaws.com" | Out-Null
    Write-Host "OIDC provider created."
} else {
    Write-Host "Existing OIDC provider reused."
}

$provider = aws iam get-open-id-connect-provider `
    --open-id-connect-provider-arn $ProviderArn | ConvertFrom-Json

if ($provider.ClientIDList -notcontains "sts.amazonaws.com") {
    aws iam add-client-id-to-open-id-connect-provider `
        --open-id-connect-provider-arn $ProviderArn `
        --client-id "sts.amazonaws.com"
    Write-Host "Added sts.amazonaws.com audience."
}

Write-Host "`n[3/7] Generating exact trust policy..." -ForegroundColor Yellow
$trust = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Principal = @{ Federated = $ProviderArn }
            Action = "sts:AssumeRoleWithWebIdentity"
            Condition = @{
                StringEquals = @{
                    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                    "token.actions.githubusercontent.com:sub" = $sub
                }
            }
        }
    )
} | ConvertTo-Json -Depth 10

$trustPath = Join-Path $PSScriptRoot "aws\github-oidc-trust-policy.json"
Set-Content -Path $trustPath -Value $trust -Encoding UTF8

Write-Host "`n[4/7] Creating/updating IAM role..." -ForegroundColor Yellow
aws iam get-role --role-name $RoleName *> $null
if ($LASTEXITCODE -ne 0) {
    aws iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document "file://$trustPath" | Out-Null
} else {
    aws iam update-assume-role-policy `
        --role-name $RoleName `
        --policy-document "file://$trustPath"
}
Write-Host "IAM role is configured."

Write-Host "`n[5/7] Updating deployment policy..." -ForegroundColor Yellow
$policyDoc = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Sid = "ElasticBeanstalkDeployment"
            Effect = "Allow"
            Action = @(
                "elasticbeanstalk:CreateApplicationVersion",
                "elasticbeanstalk:UpdateEnvironment",
                "elasticbeanstalk:DescribeApplications",
                "elasticbeanstalk:DescribeEnvironments",
                "elasticbeanstalk:DescribeEnvironmentHealth",
                "elasticbeanstalk:DescribeEnvironmentResources",
                "elasticbeanstalk:DescribeEvents",
                "elasticbeanstalk:DescribeApplicationVersions",
                "elasticbeanstalk:DescribeConfigurationSettings",
                "elasticbeanstalk:CreateStorageLocation"
            )
            Resource = "*"
        },
        @{
            Sid = "ElasticBeanstalkDeploymentBucket"
            Effect = "Allow"
            Action = @(
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:CreateBucket",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:GetBucketAcl"
            )
            Resource = @(
                "arn:aws:s3:::elasticbeanstalk-$Region-$AccountId",
                "arn:aws:s3:::elasticbeanstalk-$Region-$AccountId/*"
            )
        },
        @{
            Sid = "CloudFormationRead"
            Effect = "Allow"
            Action = @(
                "cloudformation:DescribeStacks",
                "cloudformation:DescribeStackResources"
            )
            Resource = "*"
        }
    )
} | ConvertTo-Json -Depth 10

$policyPath = Join-Path $PSScriptRoot "aws\github-eb-deploy-policy.json"
Set-Content -Path $policyPath -Value $policyDoc -Encoding UTF8

aws iam get-policy --policy-arn $PolicyArn *> $null
if ($LASTEXITCODE -ne 0) {
    aws iam create-policy `
        --policy-name $PolicyName `
        --policy-document "file://$policyPath" | Out-Null
} else {
    aws iam create-policy-version `
        --policy-arn $PolicyArn `
        --policy-document "file://$policyPath" `
        --set-as-default | Out-Null
}
aws iam attach-role-policy --role-name $RoleName --policy-arn $PolicyArn | Out-Null
Write-Host "Deployment policy is attached."

Write-Host "`n[6/7] Setting GitHub repository variable..." -ForegroundColor Yellow
gh variable set AWS_ROLE_ARN --repo "$Owner/$Repo" --body $RoleArn
Write-Host "AWS_ROLE_ARN = $RoleArn"

Write-Host "`n[7/7] Final verification..." -ForegroundColor Yellow
aws iam get-role `
    --role-name $RoleName `
    --query "Role.AssumeRolePolicyDocument.Statement[0].Condition" `
    --output json

Write-Host "`n=== SETUP COMPLETE ===" -ForegroundColor Green
Write-Host "Existing EB application/environment: $Application / $Environment"
Write-Host "No EB environment was created or deleted."
