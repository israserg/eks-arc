# Actions Runner Controller (ARC): runs GitHub Actions jobs as pods in your cluster.
# Only created when github_config_url is set, so the cluster can be built first.

locals {
  arc_enabled = var.github_config_url != "" ? 1 : 0
}

# Controller: watches GitHub and manages runner pods.
resource "helm_release" "arc_controller" {
  count = local.arc_enabled

  name             = "arc"
  namespace        = "arc-systems"
  create_namespace = true
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  version          = "0.15.1"

  depends_on = [module.eks]
}

# Secret with the GitHub credentials. ARC reads it to register runners.
resource "kubernetes_namespace" "arc_runners" {
  count = local.arc_enabled

  metadata {
    name = "arc-runners"
  }

  depends_on = [module.eks]
}

resource "kubernetes_secret" "github_credentials" {
  count = local.arc_enabled

  metadata {
    name      = "arc-github-credentials"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
  }

  data = {
    github_token = var.github_token
  }
}

# Runner scale set: the group of runner pods GitHub Actions jobs use.
# Fixed at one runner, which matches the fixed one-node cluster.
resource "helm_release" "arc_runners" {
  count = local.arc_enabled

  name       = "arc-runners"
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.15.1"

  values = [yamlencode({
    githubConfigUrl    = var.github_config_url
    githubConfigSecret = kubernetes_secret.github_credentials[0].metadata[0].name
    # Scale to zero: a runner pod is created only when a job is queued.
    # Karpenter then launches a node for it and removes the node after the job.
    minRunners = 0
    maxRunners = var.runner_max

    # Docker-in-Docker: a Docker daemon runs as a sidecar so jobs can run docker build/run/push.
    containerMode = {
      type = "dind"
    }

    template = {
      spec = {
        # Runner pods use this service account, which is linked to the ECR role via Pod Identity.
        serviceAccountName = kubernetes_service_account.arc_runner[0].metadata[0].name

        # Keep runners off the small system node: they run only on Karpenter's "runners" nodes.
        nodeSelector = {
          "karpenter.sh/nodepool" = "runners"
        }
      }
    }
  })]

  depends_on = [
    helm_release.arc_controller,
    aws_eks_pod_identity_association.arc_runner,
    kubectl_manifest.node_pool, # destroy runners before the NodePool so nodes drain cleanly
    kubernetes_limit_range_v1.arc_runners,
  ]
}

# Default resource requests for every container in the runners namespace.
# Karpenter sizes nodes from pod requests; without requests it would assume zero and pack pods badly.
resource "kubernetes_limit_range_v1" "arc_runners" {
  count = local.arc_enabled

  metadata {
    name      = "default-requests"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = "250m"
        memory = "512Mi"
      }
    }
  }
}
