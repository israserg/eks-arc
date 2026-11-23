terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    # Applies raw YAML (Karpenter NodePool/EC2NodeClass) without needing the CRDs at plan time.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }

  # Remote state in the bucket created in the console step.
  # use_lockfile stores a lock in S3 itself (Terraform 1.10+), so no DynamoDB table is needed.
  backend "s3" {
    bucket       = "tfstate-eks-34b96d0a"
    key          = "eks-arc/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
