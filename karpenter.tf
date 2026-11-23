# Karpenter: watches for pods that can't be scheduled and launches right-sized EC2 nodes for them.
# It removes the nodes again when they are empty.

# AWS side: IAM role for the controller (via Pod Identity), IAM role for the nodes it creates,
# an SQS queue + EventBridge rules for spot/maintenance notices, and the node access entry.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions           = true # permissions for Karpenter v1.x
  enable_pod_identity             = true
  create_pod_identity_association = true

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"
}

# Kubernetes side: the Karpenter controller.
resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.15.3"

  values = [yamlencode({
    replicas = 1 # one is enough for training; default is 2 for high availability
    settings = {
      clusterName       = module.eks.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }
    serviceAccount = {
      name = module.karpenter.service_account
    }
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  depends_on = [module.karpenter]
}

# EC2NodeClass: HOW nodes are built (AMI, subnets, security groups, IAM role).
resource "kubectl_manifest" "node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role             = module.karpenter.node_iam_role_name
      amiSelectorTerms = [{ alias = "al2023@latest" }]
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
    }
  })

  wait       = true # on destroy, wait for Karpenter to finish cleaning up
  depends_on = [helm_release.karpenter]
}

# NodePool: WHAT nodes may be created and WHEN they are removed.
resource "kubectl_manifest" "node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "runners" }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            # Only Free Tier eligible types: other types are rejected by the Free plan.
            { key = "node.kubernetes.io/instance-type", operator = "In", values = var.runner_instance_types },
          ]
          expireAfter = "24h" # replace nodes after a day so they stay fresh
        }
      }
      # Safety cap: never run more than 4 vCPU of runner nodes in total.
      limits = { cpu = "4" }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m" # remove a node 1 minute after its last pod is gone
      }
    }
  })

  wait       = true
  depends_on = [kubectl_manifest.node_class]
}
