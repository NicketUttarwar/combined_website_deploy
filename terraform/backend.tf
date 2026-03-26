# Committed local state: path is relative to this directory (terraform/).
# See README "Terraform state in Git" — never commit config/terraform.tfvars or config/aws.env.
terraform {
  backend "local" {
    path = "state/terraform.tfstate"
  }
}
