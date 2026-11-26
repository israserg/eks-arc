variable "region" {
  description = "AWS region for the project (must match the project's selected Region)."
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "arc-training"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (1.37 is the default with standard support)."
  type        = string
  default     = "1.37"
}

variable "node_instance_type" {
  description = "Instance type of the fixed system node (CoreDNS, ARC controller, Karpenter, Argo CD). Must be Free Tier eligible on the Free plan."
  type        = string
  default     = "m7i-flex.large"
}

variable "node_count" {
  description = "Fixed number of system nodes (min = desired = max). Runner nodes are created by Karpenter."
  type        = number
  default     = 1
}

variable "runner_instance_types" {
  description = "Instance types Karpenter may launch for runner jobs. All must be Free Tier eligible on the Free plan."
  type        = list(string)
  default     = ["t3.small", "c7i-flex.large", "m7i-flex.large"]
}

variable "runner_medium_instance_types" {
  description = "Instance types for the medium runner tier. Free Tier eligible and large enough for ~3 GiB of pod requests."
  type        = list(string)
  default     = ["c7i-flex.large", "m7i-flex.large"]
}

variable "runner_medium_max" {
  description = "Maximum number of medium runner pods (concurrent medium jobs). One fits per node at the default size."
  type        = number
  default     = 2
}

variable "runner_max" {
  description = "Maximum number of runner pods (concurrent jobs). Each needs about 1 GiB; the NodePool CPU limit also caps this."
  type        = number
  default     = 2
}

variable "github_config_url" {
  description = "GitHub repo or org that runners register to, e.g. https://github.com/<owner>/<repo>. Leave empty to skip the ARC runner step."
  type        = string
  default     = "https://github.com/israserg/eks-arc"
}

variable "app_repo_url" {
  description = "GitHub repo of the demo app. Gets its own runner scale set (runs-on: arc-app). Leave empty to skip."
  type        = string
  default     = "https://github.com/israserg/eks-demo-app"
}

variable "argocd_enabled" {
  description = "Install Argo CD and the root Application. Set false to skip."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Public Git repo Argo CD syncs from (needs root/ with Application files)."
  type        = string
  default     = "https://github.com/israserg/eks-gitops"
}

variable "github_token" {
  description = "GitHub Personal Access Token used by ARC (repo scope; for training only). Set via TF_VAR_github_token or terraform.tfvars, never commit it."
  type        = string
  default     = ""
  sensitive   = true
}
