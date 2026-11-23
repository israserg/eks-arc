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
  description = "EC2 instance type for worker nodes. t3.medium gives 2 vCPU and 4 GiB, enough for ARC."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Fixed number of worker nodes (min = desired = max). Karpenter will replace this later."
  type        = number
  default     = 1
}

variable "github_config_url" {
  description = "GitHub repo or org that runners register to, e.g. https://github.com/<owner>/<repo>. Leave empty to skip the ARC runner step."
  type        = string
  default     = ""
}

variable "github_token" {
  description = "GitHub Personal Access Token used by ARC (repo scope; for training only). Set via TF_VAR_github_token or terraform.tfvars, never commit it."
  type        = string
  default     = ""
  sensitive   = true
}
