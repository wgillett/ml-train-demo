# bootstrap

Creates the AWS-side prerequisites for Step 5/6: a least-privilege personal
IAM user for local AWS CLI/Terraform use, the ECR repository for the
training image, the GitHub OIDC provider, and the IAM role GitHub Actions
assumes through it to push images (`ci.tf` — no static AWS keys in CI).

## Applying this for the first time

Terraform needs *some* AWS credentials to create the IAM user in the first
place — it can't create the very credentials it's given to run with. Apply
this once using your AWS root or an existing admin identity (e.g. root
account credentials configured temporarily in the CLI), then switch your
day-to-day AWS CLI/Terraform usage over to the new user afterwards. This
stack's own permissions (`PowerUserAccess` + the scoped IAM policy in
`iam.tf`) are sufficient to `plan`/`apply` future changes to itself and to
Step 6's EKS module, so a second bootstrap round shouldn't be needed.

```sh
terraform init
terraform plan
terraform apply
```

## After applying

Terraform does not create an access key for the new user — creating one
would put the secret key in state. Create it manually instead:

```sh
aws iam create-access-key --user-name "$(terraform output -raw iam_user_name)"
```

Store the resulting credentials in a credential helper (aws-vault, a
locally-scoped `~/.aws/credentials` profile, etc.) — never in the repo.
Enable MFA on this user in the AWS console as well; Terraform can't do
that step for you.

## What's deliberately not here

- VPC/EKS resources — Step 6, a separate `terraform/eks/` module.

## After adding/changing the CI role (`ci.tf`)

Set the two GitHub repo variables the workflow reads, after `apply`:

```sh
gh variable set ECR_REPOSITORY_URL --body "$(terraform output -raw ecr_repository_url)"
gh variable set AWS_GITHUB_ACTIONS_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
```
