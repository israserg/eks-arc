# Second runner scale set: "arc-medium" for heavier jobs (docker build + tests).
#
# Workflows pick a size with the runs-on label:
#   runs-on: arc-runners   -> small  (about 0.5 vCPU / 1 GiB)
#   runs-on: arc-medium    -> medium (about 1.5 vCPU / 3 GiB, 50 GiB disk)
#
# It shares the same ARC controller, GitHub secret, service account (ECR push) and taint.
# What differs: its own NodePool/EC2NodeClass (node types and disk) and its own pod sizing.

# --- Karpenter side: how medium nodes are built and which types they may use ---------------

resource "kubectl_manifest" "node_class_medium" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "medium" }
    spec = {
      role             = module.karpenter.node_iam_role_name
      amiSelectorTerms = [{ alias = "al2023@latest" }]
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      # Bigger root disk than the default 20 GiB: Docker images and build layers need room.
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "50Gi"
          volumeType          = "gp3"
          deleteOnTermination = true
        }
      }]
    }
  })

  wait       = true
  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "node_pool_medium" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "medium" }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "medium"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            # Free Tier eligible types big enough for a medium runner pod (needs ~3 GiB).
            { key = "node.kubernetes.io/instance-type", operator = "In", values = var.runner_medium_instance_types },
          ]
          taints = [
            { key = "dedicated", value = "runners", effect = "NoSchedule" }
          ]
          expireAfter = "24h"
        }
      }
      limits = { cpu = "4" }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  })

  wait       = true
  depends_on = [kubectl_manifest.node_class_medium]
}

# --- ARC side: the runner scale set with explicit pod sizing --------------------------------

locals {
  # Written out in full (not containerMode = dind) because the chart only allows resource
  # customisation when you supply the whole pod spec. This mirrors the chart's dind template.
  arc_medium_values = {
    githubConfigUrl    = var.github_config_url
    githubConfigSecret = "arc-github-credentials"
    minRunners         = 0
    maxRunners         = var.runner_medium_max

    template = {
      spec = {
        serviceAccountName = "arc-runner"
        nodeSelector       = { "karpenter.sh/nodepool" = "medium" }
        tolerations = [
          { key = "dedicated", operator = "Equal", value = "runners", effect = "NoSchedule" }
        ]

        initContainers = [
          {
            name    = "init-dind-externals"
            image   = "ghcr.io/actions/actions-runner:latest"
            command = ["cp", "-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
            volumeMounts = [
              { name = "dind-externals", mountPath = "/home/runner/tmpDir" }
            ]
            resources = { requests = { cpu = "100m", memory = "128Mi" } }
          },
          {
            # Docker daemon sidecar (a native sidecar: restartPolicy Always keeps it running).
            name            = "dind"
            image           = "docker:dind"
            args            = ["dockerd", "--host=unix:///var/run/docker.sock", "--group=$(DOCKER_GROUP_GID)"]
            env             = [{ name = "DOCKER_GROUP_GID", value = "123" }]
            securityContext = { privileged = true }
            restartPolicy   = "Always"
            startupProbe = {
              exec                = { command = ["docker", "info"] }
              initialDelaySeconds = 0
              failureThreshold    = 24
              periodSeconds       = 5
            }
            volumeMounts = [
              { name = "work", mountPath = "/home/runner/_work" },
              { name = "dind-sock", mountPath = "/var/run" },
              { name = "dind-externals", mountPath = "/home/runner/externals" },
            ]
            # Image builds happen here, so this container gets most of the pod's resources.
            resources = {
              requests = { cpu = "1", memory = "2Gi" }
              limits   = { memory = "2Gi" }
            }
          },
        ]

        containers = [{
          name    = "runner"
          image   = "ghcr.io/actions/actions-runner:latest"
          command = ["/home/runner/run.sh"]
          env = [
            { name = "DOCKER_HOST", value = "unix:///var/run/docker.sock" },
            { name = "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS", value = "120" },
          ]
          volumeMounts = [
            { name = "work", mountPath = "/home/runner/_work" },
            { name = "dind-sock", mountPath = "/var/run" },
          ]
          # Memory request = limit, so a job gets its memory or fails clearly instead of
          # squeezing its neighbours.
          resources = {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { memory = "1Gi" }
          }
        }]

        volumes = [
          { name = "work", emptyDir = {} },
          { name = "dind-sock", emptyDir = {} },
          { name = "dind-externals", emptyDir = {} },
        ]
      }
    }
  }
}

resource "helm_release" "arc_medium" {
  count = local.arc_enabled

  name       = "arc-medium" # this name is the runs-on label
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.15.1"

  values = [yamlencode(local.arc_medium_values)]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.github_credentials,
    kubernetes_service_account.arc_runner,
    aws_eks_pod_identity_association.arc_runner,
    kubectl_manifest.node_pool_medium, # destroy runners before their NodePool
  ]
}
