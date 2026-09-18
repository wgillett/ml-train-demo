variable "aws_region" {
  description = "AWS region for the EKS cluster and its VPC"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "ml-train-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane. A cluster past AWS's standard support window costs an EXTRA ~$0.60/hr in \"extended support\" pricing on top of the normal ~$0.10/hr — check the current standard-support version list before applying, not just whether a version exists."
  type        = string
  default     = "1.34"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Required, no default — so this can never accidentally apply as world-open (the module's own default is 0.0.0.0/0). Set via a gitignored terraform.tfvars or -var, e.g. [\"<your-ip>/32\"]. Find your current IP with: curl -s https://checkip.amazonaws.com"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the cluster's VPC"
  type        = string
  default     = "10.60.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (kept small to limit NAT/subnet count)"
  type        = number
  default     = 2
}

variable "node_instance_types" {
  description = "CPU-only instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count (kept small — this is a demo workload, not production capacity)"
  type        = number
  default     = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "gpu_node_instance_types" {
  description = "GPU instance types for the gpu node group. g4dn.xlarge (one NVIDIA T4) is the cheapest common choice at ~$0.53/hr — still >10x the CPU node. New/personal accounts often have a ZERO quota for G instances; check before applying (see README)."
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_node_desired_size" {
  description = "GPU node count at creation. Defaults to 0 so the group costs nothing until a demo actually needs it. NOTE: the eks module ignores later changes to desired_size (so it doesn't fight autoscalers) — set this on a fresh apply, or scale the node group via the AWS CLI afterwards."
  type        = number
  default     = 0
}

variable "role_permissions_boundary_arn" {
  description = "Permissions boundary applied to every IAM role this module creates. Must match terraform/bootstrap's boundary — the ml-train-demo-admin user can only CreateRole for ml-train-demo-* roles when this exact boundary is attached (see terraform/bootstrap/iam.tf)."
  type        = string
  default     = "arn:aws:iam::aws:policy/PowerUserAccess"
}

variable "resource_prefix" {
  description = "Prefix for role names this module creates, matching the ml-train-demo-* scope the bootstrap user's IAM policy grants"
  type        = string
  default     = "ml-train-demo"
}
