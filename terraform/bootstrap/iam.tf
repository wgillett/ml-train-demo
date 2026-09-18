# Personal IAM user for local AWS CLI/Terraform use (provisioning ECR,
# the GitHub OIDC provider, and later VPC/EKS resources). GitHub Actions
# itself must never use this user's static credentials — it authenticates
# via the OIDC provider in oidc.tf and an assumed role instead.

resource "aws_iam_user" "bootstrap" {
  name = var.iam_user_name
}

# Broad operational access (ECR, EC2/VPC, EKS, S3, ...) but deliberately
# excludes IAM/Organizations management, so this user can't grant itself
# further permissions on its own.
resource "aws_iam_user_policy_attachment" "power_user" {
  user       = aws_iam_user.bootstrap.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Fills the IAM gap PowerUserAccess leaves, scoped to this project's
# resources only (never IAMFullAccess).
data "aws_iam_policy_document" "iam_bootstrap" {
  statement {
    sid    = "OidcProviderManagement"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "iam:TagOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
    ]
    resources = ["*"] # OIDC provider ARNs aren't known until created; IAM has no narrower resource type for this action
  }

  statement {
    sid    = "ScopedRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_prefix}-*"]
  }

  statement {
    sid    = "ScopedPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.resource_prefix}-*"]
  }

  statement {
    sid       = "ScopedPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_prefix}-*"]
  }
}

resource "aws_iam_policy" "iam_bootstrap" {
  name        = "${var.resource_prefix}-iam-bootstrap"
  description = "Scoped IAM management for the ${var.resource_prefix} bootstrap user: the GitHub OIDC provider plus ${var.resource_prefix}-* roles/policies only"
  policy      = data.aws_iam_policy_document.iam_bootstrap.json
}

resource "aws_iam_user_policy_attachment" "iam_bootstrap" {
  user       = aws_iam_user.bootstrap.name
  policy_arn = aws_iam_policy.iam_bootstrap.arn
}
