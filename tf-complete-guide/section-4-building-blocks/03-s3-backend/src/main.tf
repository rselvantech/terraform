provider "aws"{
    region="us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-urdrdrd-12345"
}