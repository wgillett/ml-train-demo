# bootstrap

Creates the AWS-side prerequisites for Step 5/6: a least-privilege personal
IAM user for local AWS CLI/Terraform use, the ECR repository for the
training image, and the GitHub OIDC provider (so CI can later assume a
role instead of using static keys).

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

- The GitHub Actions IAM role that trusts the OIDC provider above — that's
  created alongside the CI workflow itself (Step 5), not here, since it
  needs to reference the specific repo/workflow trust condition.
- VPC/EKS resources — Step 6, a separate `terraform/eks/` module.
