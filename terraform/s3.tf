resource "aws_s3_bucket" "site" {
  bucket = var.s3_bucket_name
}

# Allow a public bucket policy so the S3 website endpoint can serve objects over HTTP.
# CloudFront uses that endpoint as its origin so paths like /about/ resolve to about/index.html.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}
