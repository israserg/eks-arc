data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # EKS needs subnets in at least two Availability Zones. Use the first two.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"
  azs  = local.azs

  # Public subnets hold the internet-facing load balancers.
  # Private subnets hold the worker nodes, which are not reachable from the internet.
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  # One NAT gateway instead of one per AZ: cheaper, fine for training.
  # Private nodes use it to pull images and reach the EKS API.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required by EKS and the AWS Load Balancer Controller to find subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter launches nodes into subnets carrying this tag.
    "karpenter.sh/discovery" = var.cluster_name
  }
}
