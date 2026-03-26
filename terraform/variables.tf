variable "aws_region" {
  type        = string
  description = "AWS region for all resources in this stack (S3, ACM, CloudFront). Default: us-east-1 (N. Virginia); required for ACM certificates used with CloudFront."
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "This stack is single-region: aws_region must be us-east-1."
  }
}

variable "project_name" {
  type        = string
  description = "Short name used in resource names and tags."
  default     = "combined-site"
}

variable "environment" {
  type        = string
  description = "Environment label for tags (e.g. prod)."
  default     = "prod"
}

variable "s3_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for the combined static site."
}

variable "portfolio_domain_names" {
  type        = list(string)
  description = "Hostnames for portfolio CloudFront + ACM (first = primary cert domain)."
  default = [
    "nicketuttarwar.com",
    "www.nicketuttarwar.com",
  ]
}

variable "art_domain_names" {
  type        = list(string)
  description = "Hostnames for art CloudFront + ACM (first = primary cert domain)."
  default = [
    "uttarwarart.com",
    "www.uttarwarart.com",
  ]
}

variable "art_origin_path" {
  type        = string
  description = "S3 prefix for the art distribution origin (no leading slash)."
  default     = "uttarwarart"
}

variable "common_tags" {
  type        = map(string)
  description = "Extra tags merged onto all taggable resources."
  default     = {}
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront price class for both distributions."
  default     = "PriceClass_100"
}
