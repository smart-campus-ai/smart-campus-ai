module "state_backend" {
  source = "../modules/state-backend"

  name_prefix                        = var.name_prefix
  admin_principal_arns               = var.admin_principal_arns
  kms_deletion_window_in_days        = var.kms_deletion_window_in_days
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
}

# CI identity (EN-13, ADR-0012). Its inputs come from the state backend module, so the roles can only reach this bucket
# and this key. Applied by a human together with the state backend; every later apply goes through the roles it creates.
# Off by default: the workshop account has no GitHub OIDC provider and does not allow the CI roles and their boundaries
# (ADR-0014, ADR-0016). Nothing of the module is created while create_ci_roles is false.
module "github_oidc" {
  count  = var.create_ci_roles ? 1 : 0
  source = "../modules/github-oidc"

  name_prefix                = var.name_prefix
  github_repository          = var.github_repository
  allowed_regions            = var.allowed_regions
  state_bucket_arn           = module.state_backend.bucket_arn
  state_kms_key_arn          = module.state_backend.kms_key_arn
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
}
