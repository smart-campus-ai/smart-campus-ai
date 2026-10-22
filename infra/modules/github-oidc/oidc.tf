# GitHub OIDC identity provider. An account holds a single provider per URL: when the workshop account already has
# one, set create_oidc_provider = false and pass its ARN. No thumbprint: AWS validates the GitHub certificate chain with
# its own trusted CAs.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = [local.oidc_audience]

  tags = merge(var.tags, { Name = "${var.name_prefix}-github-oidc" })
}
