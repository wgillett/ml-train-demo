# Standard VPC shape for EKS: public subnets for the NAT gateway/any
# LoadBalancer services, private subnets for nodes. A single shared NAT
# gateway (not one per AZ) — the main cost/availability tradeoff here:
# cheaper (~$32/mo instead of ~$32/mo per AZ) but a single point of
# failure for node egress. Acceptable for a demo; a production cluster
# would usually want one NAT per AZ.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.resource_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Required so the EKS/AWS Load Balancer Controller can discover which
  # subnets to place cluster resources and load balancers in.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
