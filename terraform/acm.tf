resource "aws_acm_certificate" "site" {
  domain_name               = local.primary_domain
  subject_alternative_names = length(local.san_domains) > 0 ? local.san_domains : null
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn = aws_acm_certificate.site.arn
  validation_record_fqdns = [
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_name
  ]
}
