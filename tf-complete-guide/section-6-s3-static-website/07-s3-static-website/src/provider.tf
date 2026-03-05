terraform {
  required_version = "~>1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.30.0"
    }
    # random provider — generates stable random values
    # No provider block needed — requires no configuration
    random = {
      source  = "hashicorp/random"
      version = "~>3.8.1"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}