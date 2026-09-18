# CPU-only managed node group only — GPU node group, IRSA, and Argo CD
# are explicitly deferred (see CLAUDE.md). Cluster secret encryption via
# a customer-managed KMS key and control-plane log export are both left
# disabled: neither is needed for this demo and both carry a small
# ongoing cost (~$1/mo for the KMS key, plus CloudWatch Logs ingestion).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  cluster_encryption_config = {}

  # IRSA (pod-level IAM via a cluster-specific OIDC provider) is
  # explicitly deferred per CLAUDE.md — disable it here rather than
  # granting the bootstrap user IAM OIDC provider permissions for
  # something not in scope yet.
  enable_irsa = false

  create_iam_role               = true
  iam_role_name                 = "${var.resource_prefix}-eks-cluster"
  iam_role_use_name_prefix      = false
  iam_role_permissions_boundary = var.role_permissions_boundary_arn

  eks_managed_node_group_defaults = {
    iam_role_permissions_boundary = var.role_permissions_boundary_arn
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      iam_role_name            = "${var.resource_prefix}-eks-node"
      iam_role_use_name_prefix = false
    }
  }
}
