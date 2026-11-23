module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public endpoint so kubectl works from your WSL terminal.
  # Private nodes still reach the control plane through the VPC.
  cluster_endpoint_public_access = true

  # Give the identity that runs Terraform (your aws login role) admin access to the cluster.
  enable_cluster_creator_admin_permissions = true

  # Control plane logs go to CloudWatch. Disabled here to keep training costs low.
  cluster_enabled_log_types = []

  # Core add-ons EKS needs to run pods and networking.
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    # Lets pods receive AWS credentials for an IAM role (used by runners to push to ECR).
    eks-pod-identity-agent = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Karpenter attaches this security group to the nodes it launches.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  eks_managed_node_groups = {
    training = {
      # Fixed size: min = desired = max. Karpenter replaces this in a later lesson.
      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"
    }
  }
}
