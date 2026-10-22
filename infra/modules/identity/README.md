# identity

User pool Cognito de SmartCampus AI : e-mail comme identifiant, politique de mot de passe robuste, groupes `student` et `admin`, client SPA public (authorization code + PKCE, sans secret) et domaine hébergé Cognito (pas de domaine personnalisé).

Le MFA est optionnel au niveau du pool (TOTP proposé à tous) car Cognito ne sait pas l'exiger pour un seul groupe. Pour les membres de `admin`, l'exigence est contrôlée côté jetons (mécanisme à consigner dans un ADR). Les utilisateurs de test (`enable_test_users`, dev uniquement) reçoivent un mot de passe temporaire généré, stocké en SSM SecureString chiffré par la clé KMS fournie, jamais en sortie.

La protection contre les menaces (`enable_threat_protection`) passe le pool en offre Plus, facturée par utilisateur actif : désactivée par défaut.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.7 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cognito_user.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user) | resource |
| [aws_cognito_user_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_group) | resource |
| [aws_cognito_user_in_group.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_in_group) | resource |
| [aws_cognito_user_pool.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool) | resource |
| [aws_cognito_user_pool_client.spa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_cognito_user_pool_domain.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain) | resource |
| [aws_ssm_parameter.test_user_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [random_password.test_user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_token_validity_minutes"></a> [access\_token\_validity\_minutes](#input\_access\_token\_validity\_minutes) | Validity of the access token, in minutes (architecture v3: 60 at most). | `number` | `60` | no |
| <a name="input_allow_self_signup"></a> [allow\_self\_signup](#input\_allow\_self\_signup) | Let anyone create an account from the hosted UI. Off: accounts are created by an administrator or by federation (Entra ID, US06). | `bool` | `false` | no |
| <a name="input_callback_urls"></a> [callback\_urls](#input\_callback\_urls) | OAuth callback URLs of the SPA app client: the CloudFront URL of the environment (EN-21). HTTPS only, no wildcard; http://localhost is accepted for local development. | `list(string)` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protect the user pool against deletion. Keep true everywhere except short-lived sandboxes: deleting a pool deletes every user. | `bool` | `true` | no |
| <a name="input_domain_prefix"></a> [domain\_prefix](#input\_domain\_prefix) | Prefix of the Cognito hosted domain (<prefix>.auth.<region>.amazoncognito.com). It is unique per region across all AWS accounts. Null uses "<name\_prefix>-auth". | `string` | `null` | no |
| <a name="input_enable_test_users"></a> [enable\_test\_users](#input\_enable\_test\_users) | Create the users described in test\_users, with a generated temporary password stored in SSM Parameter Store. Development only: never enable in prod. | `bool` | `false` | no |
| <a name="input_enable_threat_protection"></a> [enable\_threat\_protection](#input\_enable\_threat\_protection) | Enable Cognito threat protection (advanced security: compromised credentials and adaptive authentication). Requires the Plus feature plan, which is billed per monthly active user: leave off where the account does not provide it. | `bool` | `false` | no |
| <a name="input_id_token_validity_minutes"></a> [id\_token\_validity\_minutes](#input\_id\_token\_validity\_minutes) | Validity of the ID token, in minutes. | `number` | `60` | no |
| <a name="input_logout_urls"></a> [logout\_urls](#input\_logout\_urls) | Sign-out URLs of the SPA app client: the CloudFront URL of the environment (EN-21). HTTPS only, no wildcard; http://localhost is accepted for local development. | `list(string)` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_oauth_scopes"></a> [oauth\_scopes](#input\_oauth\_scopes) | OAuth scopes the SPA app client may request. | `list(string)` | <pre>[<br/>  "openid",<br/>  "email",<br/>  "profile"<br/>]</pre> | no |
| <a name="input_password_minimum_length"></a> [password\_minimum\_length](#input\_password\_minimum\_length) | Minimum password length. Upper case, lower case, digit and symbol are always required. | `number` | `12` | no |
| <a name="input_refresh_token_rotation_grace_period_seconds"></a> [refresh\_token\_rotation\_grace\_period\_seconds](#input\_refresh\_token\_rotation\_grace\_period\_seconds) | Time during which the rotated-out refresh token stays valid, to allow client retries. 0 invalidates it immediately. | `number` | `0` | no |
| <a name="input_refresh_token_validity_days"></a> [refresh\_token\_validity\_days](#input\_refresh\_token\_validity\_days) | Validity of the refresh token, in days. | `number` | `30` | no |
| <a name="input_supported_identity_providers"></a> [supported\_identity\_providers](#input\_supported\_identity\_providers) | Identity providers enabled on the SPA app client. Add the Entra ID provider name here once federation is configured (US06). | `list(string)` | <pre>[<br/>  "COGNITO"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_temporary_password_validity_days"></a> [temporary\_password\_validity\_days](#input\_temporary\_password\_validity\_days) | Number of days an administrator-created account can be activated with its temporary password. | `number` | `7` | no |
| <a name="input_test_users"></a> [test\_users](#input\_test\_users) | Test users by stable key (lowercase letters, digits, hyphens). Created only when enable\_test\_users is true. The password is generated, never an input. | <pre>map(object({<br/>    email = string<br/>    group = string<br/>  }))</pre> | `{}` | no |
| <a name="input_test_users_kms_key_arn"></a> [test\_users\_kms\_key\_arn](#input\_test\_users\_kms\_key\_arn) | ARN of the customer-managed KMS key (EN-14, data domain) that encrypts the SecureString parameters holding the test user passwords. Required when enable\_test\_users is true. | `string` | `null` | no |
| <a name="input_threat_protection_mode"></a> [threat\_protection\_mode](#input\_threat\_protection\_mode) | Threat protection mode when enable\_threat\_protection is true: AUDIT only records risk, ENFORCED also blocks or challenges risky sign-ins. | `string` | `"ENFORCED"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | ID of the SPA app client (public, no secret). |
| <a name="output_group_names"></a> [group\_names](#output\_group\_names) | Names of the user pool groups, as they appear in the cognito:groups claim. |
| <a name="output_hosted_ui_base_url"></a> [hosted\_ui\_base\_url](#output\_hosted\_ui\_base\_url) | Base URL of the Cognito hosted domain (/oauth2/authorize, /oauth2/token, /logout). |
| <a name="output_issuer_url"></a> [issuer\_url](#output\_issuer\_url) | Token issuer (iss claim) and OIDC discovery base URL of the user pool. |
| <a name="output_test_user_password_parameter_names"></a> [test\_user\_password\_parameter\_names](#output\_test\_user\_password\_parameter\_names) | SSM parameter names (not the values) holding the test user temporary passwords, by test user key. Empty unless enable\_test\_users is true. |
| <a name="output_user_pool_arn"></a> [user\_pool\_arn](#output\_user\_pool\_arn) | ARN of the Cognito user pool (API Gateway Cognito authorizer, pre-token trigger permission). |
| <a name="output_user_pool_id"></a> [user\_pool\_id](#output\_user\_pool\_id) | ID of the Cognito user pool. |
<!-- END_TF_DOCS -->
