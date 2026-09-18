# CPU-only managed node group only — GPU node group, IRSA, and Argo CD
# are explicitly deferred (see CLAUDE.md). Cluster secret encryption via
# a customer-managed KMS key is left disabled: not needed for this demo
# and carries a small ongoing cost (~$1/mo for the KMS key).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public access is restricted to var.cluster_endpoint_public_access_cidrs
  # (required, no default) rather than the module's 0.0.0.0/0 default —
  # otherwise the Kubernetes API endpoint is reachable from the entire
  # internet (auth still required to do anything, but there's no reason
  # to accept connections from IPs that could never authenticate anyway).
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Security-relevant control-plane audit trail. Omits controllerManager/
  # scheduler logs (operational, not security-relevant, and add volume)
  # to keep the small CloudWatch Logs cost this adds down.
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  cluster_encryption_config = {}

  # Without this, the module does NOT automatically grant the creating
  # IAM principal any Kubernetes access — IAM auth to AWS succeeds but
  # kubectl fails with "the server has asked for the client to provide
  # credentials" since there's no RBAC mapping at all for that identity.
  enable_cluster_creator_admin_permissions = true

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

    # Single-GPU node group for the GPU training demo. The EKS NVIDIA AMI
    # ships the driver and container toolkit; the device plugin that
    # advertises nvidia.com/gpu to the scheduler is applied separately
    # (k8s/gpu/nvidia-device-plugin.yaml). Tainted so only GPU work lands
    # on the expensive node. Sized to 0 by default — see the variable.
    gpu = {
      # Stable name (no timestamp suffix) so `aws eks update-nodegroup-config
      # --nodegroup-name gpu` works without looking the name up first.
      name            = "gpu"
      use_name_prefix = false

      instance_types = var.gpu_node_instance_types
      ami_type       = "AL2023_x86_64_NVIDIA"
      capacity_type  = "ON_DEMAND"

      desired_size = var.gpu_node_desired_size
      min_size     = 0
      max_size     = 1

      iam_role_name            = "${var.resource_prefix}-eks-gpu-node"
      iam_role_use_name_prefix = false

      # What k8s/gpu/nvidia-device-plugin.yaml's nodeSelector keys on.
      labels = {
        accelerator = "nvidia-gpu"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      # The CUDA-build training image is several GB uncompressed; the
      # default 20 GB root volume is too tight once the AMI's own driver
      # stack is on it.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }
    }
  }
}
