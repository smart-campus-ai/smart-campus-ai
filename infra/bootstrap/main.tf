module "state_backend" {
  source = "../modules/state-backend"

  name_prefix                        = var.name_prefix
  admin_principal_arns               = var.admin_principal_arns
  kms_deletion_window_in_days        = var.kms_deletion_window_in_days
  noncurrent_version_expiration_days = var.noncurrent_version_expiration_days
}
