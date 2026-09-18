# IAM role GitHub Actions assumes via the OIDC provider in oidc.tf —
# no static AWS keys in CI. Scoped to push events on one branch of one
# repo, and permitted only to push to the one ECR repo this project uses.

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub's `sub` claim now embeds immutable numeric owner/repo IDs
    # (e.g. "repo:org@123/repo@456:ref:refs/heads/main") rather than the
    # classic "repo:org/repo:ref:refs/heads/main" format, so matching it
    # directly is fragile. AWS also requires (as of a hardening rollout)
    # that a GitHub OIDC trust policy condition on sub or job_workflow_ref
    # specifically — arbitrary claims like `repository`/`ref` alone are
    # rejected at the API level. job_workflow_ref pins this to one exact
    # workflow file and branch, which is what we want anyway.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_repository}/.github/workflows/ci.yml@refs/heads/${var.github_ci_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.resource_prefix}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  permissions_boundary = local.role_permissions_boundary_arn
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    # ecr:GetAuthorizationToken has no resource-level permissions in AWS —
    # it must be "*".
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrl",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.training_image.arn]
  }
}

resource "aws_iam_policy" "github_actions_ecr_push" {
  name        = "${var.resource_prefix}-github-actions-ecr-push"
  description = "Push access to the ${var.ecr_repository_name} ECR repo, for the GitHub Actions CI role only"
  policy      = data.aws_iam_policy_document.github_actions_ecr_push.json
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr_push.arn
}
