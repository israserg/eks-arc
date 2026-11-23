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
    minRunners         = 1
    maxRunners         = 1
  })]

  depends_on = [helm_release.arc_controller]
}
