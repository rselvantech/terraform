terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.30.0"
    }

  }
}

provider "aws" {
  region = "us-east-2"
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}