resource "random_id" "bucket-suffix" {
  byte_length = 6
}

resource "aws_s3_bucket" "example_bucket" {
  bucket = "example-bucket-${random_id.bucket-suffix.hex}"
}

output "bucket_name" {
  description = "Created Bucket name"
  value       = aws_s3_bucket.example_bucket.bucket
}