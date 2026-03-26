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
  description = "Short name used in resource names and tags for this website stack."
  default     = "website"
}

variable "environment" {
  type        = string
  description = "Environment label for tags (e.g. prod)."
  default     = "prod"
}

variable "s3_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for this static website."
}

variable "domain_names" {
  type        = list(string)
  description = "Hostnames for the same static site: CloudFront alternate domain names and ACM subject names. Primary certificate domain is the first element; additional entries are SANs (e.g. apex plus www)."
  default = [
    "nicketuttarwar.com",
    "www.nicketuttarwar.com",
  ]
}

variable "common_tags" {
  type        = map(string)
  description = "Extra tags merged onto all taggable resources."
  default     = {}
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront price class for the distribution."
  default     = "PriceClass_100"
}
