# Trust policies. Both conditions use StringEquals (never StringLike): the "sub" claim is pinned verbatim to the
# repository and to the pull_request event (plan) or to the GitHub environment (apply). Federated principals have no
# aws:SourceArn / aws:SourceAccount; the pinned "sub" and "aud" claims play the confused-deputy role here.
data "aws_iam_policy_document" "trust_plan" {
  statement {
    sid     = "GitHubOidcPullRequest"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.plan_sub]
    }
  }
}

data "aws_iam_policy_document" "trust_apply" {
  for_each = local.environments

  statement {
    sid     = "GitHubOidcEnvironment"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.apply_sub[each.key]]
    }
  }
}
