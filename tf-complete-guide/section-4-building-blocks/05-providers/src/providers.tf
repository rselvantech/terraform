terraform {
  required_version = ">= 1.0"
  required_providers {
    whatever = {                 # ← intentionally wrong local name
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "whatever" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-yourname-12345"
}
