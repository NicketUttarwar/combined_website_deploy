# Public read on objects: required for the S3 *website* endpoint (CloudFront's HTTP origin).
# Origin Access Control applies only to the S3 REST API; it cannot sign requests to the website hostname.
data "aws_iam_policy_document" "public_read_site" {
  statement {
    sid = "PublicReadGetObject"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.site.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.public_read_site.json

  depends_on = [
    aws_s3_bucket_public_access_block.site,
  ]
}
