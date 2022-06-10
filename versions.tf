terraform {
  required_version = ">= 0.13"
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "~>2.2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}
