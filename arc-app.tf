# Runner scale set for the demo app repo (israserg/eks-demo-app).
#
# An ARC scale set registers to ONE repo (or org), so the runners created for eks-arc cannot
# serve a different repo. This adds a third scale set, "arc-app", for the app repo.
#   runs-on: arc-app
#
# It reuses the controller, GitHub secret, service account (ECR push) and the "runners"
# NodePool (same size as the small tier).

resource "helm_release" "arc_app" {
  count = var.app_repo_url != "" ? local.arc_enabled : 0

  name       = "arc-app" # this name is the runs-on label
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.15.1"

  values = [yamlencode({
    githubConfigUrl    = var.app_repo_url
    githubConfigSecret = kubernetes_secret.github_credentials[0].metadata[0].name
    minRunners         = 0
    maxRunners         = 1 # both small scale sets share the NodePool's 4 vCPU cap

    containerMode = {
      type = "dind"
    }

    template = {
      spec = {
        serviceAccountName = kubernetes_service_account.arc_runner[0].metadata[0].name
        nodeSelector       = { "karpenter.sh/nodepool" = "runners" }
        tolerations = [
          { key = "dedicated", operator = "Equal", value = "runners", effect = "NoSchedule" }
        ]
      }
    }
  })]

  depends_on = [
    helm_release.arc_controller,
    aws_eks_pod_identity_association.arc_runner,
    kubectl_manifest.node_pool,
    kubernetes_limit_range_v1.arc_runners,
  ]
}
