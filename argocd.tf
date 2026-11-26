# Argo CD: GitOps controller. It watches a Git repo and keeps the cluster equal to it.
# Terraform installs Argo CD and one "root" Application; after that, apps are added by
# committing to the gitops repo, not by changing Terraform.
# Only created when argocd_enabled = true.

locals {
  argocd_enabled = var.argocd_enabled ? 1 : 0
}

resource "helm_release" "argocd" {
  count = local.argocd_enabled

  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.19.1" # Argo CD v3.6.3

  values = [yamlencode({
    # Not needed for a local-admin training setup; each one is a pod we don't have to run.
    dex           = { enabled = false } # SSO login
    notifications = { enabled = false }

    # Single replicas everywhere (stated explicitly; server/repoServer are set below).
    applicationSet = { replicas = 1 }

    # Requests let the scheduler place pods sensibly and show up in "kubectl top" comparisons.
    # Starting estimates; we will measure real usage and adjust.
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    server = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }

    # The UI is reached with "kubectl port-forward", so the Service stays ClusterIP
    # (default). No load balancer, no public exposure, no extra cost.
  })]

  depends_on = [module.eks]
}

# The "root" Application: tells Argo CD to sync the root/ folder of the gitops repo.
# Every file in root/ is itself an Application (app-of-apps pattern).
# Raw YAML via kubectl_manifest, because the Application CRD doesn't exist until Argo CD is installed.
resource "kubectl_manifest" "argocd_root_app" {
  count = local.argocd_enabled

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = "HEAD"
        path           = "root"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
