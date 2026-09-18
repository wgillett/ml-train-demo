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

# Every role this user can create must carry this permissions boundary,
# capping its *effective* permissions at what the bootstrap user already
# has — no matter what policy later gets attached to it or what trust
# policy is set on it. This is what actually blocks the classic
# CreateRole + AttachRolePolicy(AdministratorAccess) + PassRole
# privilege-escalation chain: attaching an admin policy to a
# boundary-capped role doesn't grant admin, since effective permissions
# are the *intersection* of the attached policy and the boundary. Reusing
# the AWS-managed PowerUserAccess policy (rather than a bespoke boundary
# policy) also means the boundary itself can't be tampered with by this
# user — it's not something they can edit.
#
# Any aws_iam_role created under this project (the CI role in Step 5, the
# EKS cluster/node roles in Step 6) must set
# permissions_boundary = local.role_permissions_boundary_arn, or its
# creation will be denied by the condition below.
locals {
  role_permissions_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Fills the IAM gap PowerUserAccess leaves, scoped to this project's
# resources only (never IAMFullAccess).
data "aws_iam_policy_document" "iam_bootstrap" {
  statement {
    # Self-scoped: lets Terraform read and reconcile tags on its own
    # aws_iam_user/aws_iam_user_policy_attachment resources when run as
    # this same user (as opposed to the one-time admin credential used
    # for the very first apply). Tagging is metadata only — granting it
    # here carries none of the escalation risk that role/policy
    # management does.
    sid    = "SelfUserManagement"
    effect = "Allow"
    actions = [
      "iam:GetUser",
      "iam:ListUserPolicies",
      "iam:ListAttachedUserPolicies",
      "iam:TagUser",
      "iam:UntagUser",
    ]
    resources = [aws_iam_user.bootstrap.arn]
  }

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
    # The GitHub OIDC provider's ARN is deterministic from its URL, so this
    # can (and must) be scoped exactly — "*" would let this user create or
    # modify *any* OIDC provider, including one trusting an issuer they
    # control, as a federation-based backdoor into the account.
    resources = [aws_iam_openid_connect_provider.github_actions.arn]
  }

  statement {
    # Split from ScopedRoleManagement below: the iam:PermissionsBoundary
    # condition key is only present in CreateRole's request context. If
    # this condition were combined into one statement with GetRole,
    # AttachRolePolicy, etc. (as it was originally), the missing context
    # key on those other actions would make the condition evaluate false
    # and silently deny them too — not just CreateRole.
    sid       = "ScopedRoleCreate"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.role_permissions_boundary_arn]
    }
  }

  statement {
    # EKS checks for its own AWS-owned service-linked role before
    # creating a managed node group — a different role, outside the
    # ml-train-demo-* prefix, that the ScopedRoleManagement statement
    # below deliberately doesn't cover. Scoped to this one specific SLR.
    sid       = "EksNodegroupServiceLinkedRoleRead"
    effect    = "Allow"
    actions   = ["iam:GetRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"]
  }

  statement {
    # Split from the read above for the same reason ScopedRoleCreate is
    # split from ScopedRoleManagement: iam:AWSServiceName only exists in
    # CreateServiceLinkedRole's request context, so combining it with
    # GetRole in one statement would silently deny GetRole too.
    sid       = "EksNodegroupServiceLinkedRoleCreate"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks-nodegroup.amazonaws.com"]
    }
  }

  statement {
    sid    = "ScopedRoleManagement"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
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
      "iam:GetPolicyVersion",
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

    # Defense in depth alongside the permissions boundary above: even
    # though a boundary-capped role can't exceed PowerUserAccess, this
    # also stops the role from being handed to compute services (Lambda,
    # EC2, ...) it was never meant to run as — only EKS, the one service
    # this project actually needs to pass a role to.
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com"]
    }
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
