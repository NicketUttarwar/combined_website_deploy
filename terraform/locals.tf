locals {
  # One website; domain_names lists hostnames (e.g. apex + www) for ACM and CloudFront aliases.
  merged_tags = merge(
    {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.common_tags,
  )

  primary_domain = var.domain_names[0]
  san_domains    = length(var.domain_names) > 1 ? slice(var.domain_names, 1, length(var.domain_names)) : []
}
