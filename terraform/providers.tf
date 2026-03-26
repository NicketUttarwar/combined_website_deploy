# Single region: S3, ACM, CloudFront, and all other AWS resources use us-east-1 (var.aws_region).
# https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-requirements.html
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.merged_tags
  }
}
