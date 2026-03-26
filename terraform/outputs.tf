output "s3_bucket_id" {
  description = "S3 bucket name (use for aws s3 sync)."
  value       = aws_s3_bucket.site.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_portfolio_distribution_id" {
  description = "CloudFront distribution ID for the portfolio domain(s)."
  value       = aws_cloudfront_distribution.portfolio.id
}

output "cloudfront_portfolio_domain_name" {
  description = "CloudFront domain name (*.cloudfront.net) for DNS at Network Solutions — portfolio."
  value       = aws_cloudfront_distribution.portfolio.domain_name
}

output "cloudfront_art_distribution_id" {
  description = "CloudFront distribution ID for the art domain(s)."
  value       = aws_cloudfront_distribution.art.id
}

output "cloudfront_art_domain_name" {
  description = "CloudFront domain name (*.cloudfront.net) for DNS at Network Solutions — art."
  value       = aws_cloudfront_distribution.art.domain_name
}

output "acm_portfolio_certificate_arn" {
  description = "ACM certificate ARN (AWS requires us-east-1 for CloudFront) for portfolio alternate domain names."
  value       = aws_acm_certificate.portfolio.arn
}

output "acm_art_certificate_arn" {
  description = "ACM certificate ARN (AWS requires us-east-1 for CloudFront) for art alternate domain names."
  value       = aws_acm_certificate.art.arn
}

output "acm_portfolio_validation_records" {
  description = "ACM DNS validation CNAMEs for the portfolio certificate (add at Network Solutions)."
  value = [
    for dvo in aws_acm_certificate.portfolio.domain_validation_options : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ]
}

output "acm_art_validation_records" {
  description = "ACM DNS validation CNAMEs for the art certificate (add at Network Solutions)."
  value = [
    for dvo in aws_acm_certificate.art.domain_validation_options : {
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
