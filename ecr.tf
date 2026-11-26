# ECR repositories are owned by the separate "foundation" stack (./foundation), so they
# survive a destroy of this cluster stack. Apply ./foundation FIRST; this stack only looks
# the repositories up (plan fails here if they do not exist yet).
#
# Images:  eks-arc-demo        (built by the eks-demo-app workflow)
# Charts:  charts/demo         (Helm chart pushed as an OCI artifact)

data "aws_ecr_repository" "demo" {
  name = "eks-arc-demo"
}

data "aws_ecr_repository" "demo_chart" {
  name = "charts/demo"
}

# Identity for the runner pods. Only ECR push is allowed, nothing else.
data "aws_iam_policy_document" "arc_runner_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "arc_runner" {
  count = local.arc_enabled

  name               = "${var.cluster_name}-arc-runner"
  assume_role_policy = data.aws_iam_policy_document.arc_runner_trust.json
}

data "aws_iam_policy_document" "arc_runner_ecr" {
  # Logging in to ECR is account-wide, so it needs "*".
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push permissions are limited to the demo image repository and the demo chart repository.
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = [data.aws_ecr_repository.demo.arn, data.aws_ecr_repository.demo_chart.arn]
  }
}

resource "aws_iam_role_policy" "arc_runner_ecr" {
  count = local.arc_enabled

  name   = "ecr-push"
  role   = aws_iam_role.arc_runner[0].id
  policy = data.aws_iam_policy_document.arc_runner_ecr.json
}

# Kubernetes service account used by the runner pods.
resource "kubernetes_service_account" "arc_runner" {
  count = local.arc_enabled

  metadata {
    name      = "arc-runner"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
  }
}

# Pod Identity link: pods using this service account in arc-runners get the role above.
resource "aws_eks_pod_identity_association" "arc_runner" {
  count = local.arc_enabled

  cluster_name    = module.eks.cluster_name
  namespace       = "arc-runners"
  service_account = kubernetes_service_account.arc_runner[0].metadata[0].name
  role_arn        = aws_iam_role.arc_runner[0].arn
}
