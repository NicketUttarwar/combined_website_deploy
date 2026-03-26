# State migration only: legacy resource addresses renamed to `site`. Safe for fresh state (no-op).
moved {
  from = aws_cloudfront_distribution.portfolio
  to   = aws_cloudfront_distribution.site
}

moved {
  from = aws_acm_certificate.portfolio
  to   = aws_acm_certificate.site
}

moved {
  from = aws_acm_certificate_validation.portfolio
  to   = aws_acm_certificate_validation.site
}
