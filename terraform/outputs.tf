output "s3_bucket_id" {
  description = "S3 bucket name (use for aws s3 sync)."
  value       = aws_s3_bucket.site.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN."
  value       = aws_s3_bucket.site.arn
}

output "s3_website_endpoint" {
  description = "S3 static website hostname (HTTP). CloudFront uses this origin; useful for debugging."
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (use for invalidations and DNS; aliases come from domain_names)."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (*.cloudfront.net) for DNS at your registrar — point www (and apex via forwarding/ALIAS as applicable)."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (us-east-1) attached to CloudFront for domain_names."
  value       = aws_acm_certificate.site.arn
}

output "acm_validation_records" {
  description = "ACM DNS validation CNAMEs for the certificate (add at your DNS host)."
  value = [
    for dvo in aws_acm_certificate.site.domain_validation_options : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ]
}

output "project_tag_value" {
  description = "Default Project tag value (for list-tagged-resources.sh when TAG_VALUE is unset)."
  value       = var.project_name
}
