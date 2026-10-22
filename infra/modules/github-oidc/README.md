# github-oidc

Identité CI de GitHub Actions vers AWS, sans clé longue durée (EN-13, ADR-0012) : fournisseur OIDC GitHub, un rôle `plan` en lecture seule, un rôle `apply` par environnement, une permissions boundary CI et une boundary workload par environnement.

| Élément | Nom | Confiance (`sub`) |
|---|---|---|
| Rôle plan | `<préfixe>-gha-plan` | `repo:<org>/<repo>:pull_request` (lecture du state `dev/*` uniquement, aucune écriture S3) |
| Rôle apply dev | `<préfixe>-gha-apply-dev` | `repo:<org>/<repo>:environment:dev` |
| Rôle apply prod | `<préfixe>-gha-apply-prod` | `repo:<org>/<repo>:environment:prod` |
| Boundary CI | `<préfixe>-ci-boundary` | portée par les trois rôles ci-dessus |
| Boundary workload dev | `<préfixe>-dev-workload-boundary` | exigée sur tout rôle créé par le rôle apply dev ; plafond limité à `<préfixe>-dev-*` |
| Boundary workload prod | `<préfixe>-prod-workload-boundary` | exigée sur tout rôle créé par le rôle apply prod ; plafond limité à `<préfixe>-prod-*` |

Les conditions de confiance utilisent `StringEquals` (jamais `StringLike`) sur `aud` (`sts.amazonaws.com`) et `sub`. La durée de session maximale est de 3600 secondes.

Utilisé par `infra/bootstrap` (seul apply local, ADR-0009). `name_prefix` est le préfixe projet (`sc`), pas un préfixe d'environnement : les ressources d'un environnement sont limitées à `<préfixe>-<env>-*`.

Après l'apply du bootstrap, renseigner les variables GitHub (jamais des secrets) : `AWS_PLAN_ROLE_ARN` au niveau du dépôt (les jobs `pull_request` n'ont pas d'environnement), `AWS_APPLY_ROLE_ARN` dans chaque environnement GitHub (`dev`, `prod`) avec l'ARN du rôle correspondant.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.ci_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.workload_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.plan_deny](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.plan_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.plan_read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.apply_cdn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_compute](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_edge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_iam](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apply_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ci_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_deny](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust_apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.workload_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions in which the apply roles may manage name-scoped resources: the main region plus us-east-1 for CloudFront-scoped WAF and ACM. Used to build regional ARNs. | `list(string)` | n/a | yes |
| <a name="input_create_oidc_provider"></a> [create\_oidc\_provider](#input\_create\_oidc\_provider) | Create the GitHub OIDC identity provider. Set to false when the account already has one (an account holds a single provider per URL) and pass its ARN in existing\_oidc\_provider\_arn. | `bool` | `true` | no |
| <a name="input_existing_oidc_provider_arn"></a> [existing\_oidc\_provider\_arn](#input\_existing\_oidc\_provider\_arn) | ARN of the existing GitHub OIDC identity provider (token.actions.githubusercontent.com). Required when create\_oidc\_provider is false, must be null otherwise. | `string` | `null` | no |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | GitHub repository allowed to assume the CI roles, as <owner>/<repo>. It is pinned verbatim in the "sub" claim of every trust policy, so wildcards are refused. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Project prefix of the CI identity resources (roles <prefix>-gha-*, policies <prefix>-ci-boundary and <prefix>-<env>-workload-boundary). Per-environment resources are scoped by <prefix>-dev-* and <prefix>-prod-*, so this is the project prefix (for example "sc"), not an environment prefix. | `string` | n/a | yes |
| <a name="input_state_bucket_arn"></a> [state\_bucket\_arn](#input\_state\_bucket\_arn) | ARN of the shared OpenTofu state bucket (output of the state-backend module). The apply roles get read/write on <env>/* only; the plan role gets read on dev/* only and no write. | `string` | n/a | yes |
| <a name="input_state_kms_key_arn"></a> [state\_kms\_key\_arn](#input\_state\_kms\_key\_arn) | ARN of the state KMS key (output of the state-backend module). The CI roles get usage only; destructive actions are denied. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apply_role_arns"></a> [apply\_role\_arns](#output\_apply\_role\_arns) | ARNs of the apply roles, keyed by environment (dev, prod). Store each one as the AWS\_APPLY\_ROLE\_ARN variable of the matching GitHub environment. |
| <a name="output_ci_boundary_arn"></a> [ci\_boundary\_arn](#output\_ci\_boundary\_arn) | ARN of the permissions boundary attached to the CI roles. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub OIDC identity provider used by the trust policies (created here or passed in). |
| <a name="output_plan_role_arn"></a> [plan\_role\_arn](#output\_plan\_role\_arn) | ARN of the read-only plan role. Store it as the repository-level GitHub variable AWS\_PLAN\_ROLE\_ARN: pull\_request jobs run outside any environment. |
| <a name="output_workload_boundary_arns"></a> [workload\_boundary\_arns](#output\_workload\_boundary\_arns) | ARNs of the permissions boundaries that every role created by an apply role must carry, keyed by environment (dev, prod). A stack sets the boundary of its own environment as permissions\_boundary on every aws\_iam\_role. |
<!-- END_TF_DOCS -->
