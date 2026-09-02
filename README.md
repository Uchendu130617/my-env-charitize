# Charitize GitHub Actions → AWS Elastic Beanstalk OIDC CI/CD

This package is designed for the existing AWS resources:

- AWS account: `299332719369`
- Region: `us-east-1`
- Elastic Beanstalk application: `charitize`
- Elastic Beanstalk environment: `my-env`
- GitHub repository: `Uchendu130617/my-env-charitize`
- GitHub branch: `main`
- OIDC role: `GitHubActions-Charitize-EB`

## Important

This setup uses GitHub OIDC. No AWS access key or secret access key is stored in GitHub.

The setup script uses your already-authenticated local AWS CLI and GitHub CLI only to reconcile the existing OIDC provider, IAM role, policy, and GitHub repository variable.

Run PowerShell as the same user whose AWS CLI is already configured.

## Files

- `setup-cicd.ps1` — reconciles AWS OIDC/IAM and the GitHub repository variable.
- `aws/github-oidc-trust-policy.json` — generated/updated trust policy.
- `aws/github-eb-deploy-policy.json` — deployment permissions.
- `.github/workflows/deploy-charitize.yml` — production deployment workflow.
- `.github/workflows/oidc-smoke-test.yml` — one-time OIDC smoke test. Delete after the first successful test.

## Run

From this package directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-cicd.ps1
```

Then copy the generated `.github/workflows/deploy-charitize.yml` into the repository and push it.

The setup script also sets the repository variable:

`AWS_ROLE_ARN`

No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` GitHub variable/secret is required.

## Deployment

Every push to `main`:

1. Checks out the Laravel application.
2. Requests a short-lived GitHub OIDC token.
3. Exchanges it for temporary AWS credentials.
4. Packages the repository.
5. Uploads the package to Elastic Beanstalk's S3 deployment bucket.
6. Creates an Elastic Beanstalk application version.
7. Updates `my-env`.
8. Waits for the deployment to finish.

The workflow does not create a second Elastic Beanstalk environment.
