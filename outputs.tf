output "cluster_name" {
  description = "EKS cluster name, used by aws eks update-kubeconfig."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository the build workflow pushes images to."
  value       = data.aws_ecr_repository.demo.repository_url
}

output "argocd_access" {
  description = "How to reach the Argo CD UI (https://localhost:8080) and read the initial admin password."
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443   |   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
