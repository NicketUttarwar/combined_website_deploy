locals {
  merged_tags = merge(
    {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.common_tags,
  )

  portfolio_primary_domain = var.portfolio_domain_names[0]
  portfolio_san_domains    = length(var.portfolio_domain_names) > 1 ? slice(var.portfolio_domain_names, 1, length(var.portfolio_domain_names)) : []

  art_primary_domain = var.art_domain_names[0]
  art_san_domains    = length(var.art_domain_names) > 1 ? slice(var.art_domain_names, 1, length(var.art_domain_names)) : []
}
