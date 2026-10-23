# Cognito user pool, groups student and admin, public SPA client (authorization code + PKCE, no secret).
#
# The callback and logout URLs come from the site, which needs the API origin, which needs the user pool ARN for its
# authorizer. This is not a dependency cycle: inside the identity module only the app client reads the URLs, while the
# user pool (the only resource the API needs) does not.
#
# TODO(US06): pre-token trigger (module.pre_token) and Entra ID federation; the identity module has no input for the
# Lambda trigger yet.
module "identity" {
  source = "../../modules/identity"

  name_prefix         = var.name_prefix
  domain_prefix       = local.cognito_domain_prefix
  callback_urls       = local.spa_callback_urls
  logout_urls         = local.spa_callback_urls
  deletion_protection = var.enable_deletion_protection
}
