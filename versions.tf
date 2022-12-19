terraform {
  required_version = ">= 0.13"
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "~>2.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}
