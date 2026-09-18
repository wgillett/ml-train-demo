# Lets GitHub Actions assume an IAM role via OIDC instead of using static
# AWS keys in CI. The role itself (trusting this provider, scoped to this
# repo) is created separately when the CI workflow is implemented.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub has rotated its root CA before; keeping both the current and
  # prior intermediate thumbprints avoids a silent break on the next one.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}
