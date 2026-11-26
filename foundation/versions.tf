terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same bucket as the cluster stack, different key: a separate state, so destroying the
  # cluster stack can never touch what is defined here.
  backend "s3" {
    bucket       = "tfstate-eks-34b96d0a"
    key          = "foundation/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
