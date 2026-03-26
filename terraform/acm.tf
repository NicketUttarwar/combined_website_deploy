resource "aws_acm_certificate" "portfolio" {
  domain_name               = local.portfolio_primary_domain
  subject_alternative_names = length(local.portfolio_san_domains) > 0 ? local.portfolio_san_domains : null
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "art" {
  domain_name               = local.art_primary_domain
  subject_alternative_names = length(local.art_san_domains) > 0 ? local.art_san_domains : null
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "portfolio" {
  certificate_arn = aws_acm_certificate.portfolio.arn
  validation_record_fqdns = [
    for dvo in aws_acm_certificate.portfolio.domain_validation_options : dvo.resource_record_name
  ]
}

resource "aws_acm_certificate_validation" "art" {
  certificate_arn = aws_acm_certificate.art.arn
  validation_record_fqdns = [
    for dvo in aws_acm_certificate.art.domain_validation_options : dvo.resource_record_name
  ]
}
