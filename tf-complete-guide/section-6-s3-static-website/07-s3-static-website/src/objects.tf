resource "aws_s3_object" "index" {
  # MANDATORY — target bucket
  bucket = aws_s3_bucket.static_website.id

  # MANDATORY — the S3 key (path/filename inside the bucket)
  key = "index.html"

  # OPTIONAL — local file to upload
  # Path is relative to the directory where terraform commands are run
  source = "build/index.html"

  # OPTIONAL — MD5 hash of the local file
  # Triggers re-upload whenever the file content changes
  # Without this, editing index.html would not cause Terraform to re-upload
  etag = filemd5("build/index.html")

  # OPTIONAL — MIME type sent to browsers
  # Without this, S3 serves the file as application/octet-stream
  # which causes browsers to download rather than render the HTML
  content_type = "text/html"
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.static_website.id
  key          = "error.html"
  source       = "build/error.html"
  etag         = filemd5("build/error.html")
  content_type = "text/html"
}