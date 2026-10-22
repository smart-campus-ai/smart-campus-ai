<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_data.invoke](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_function_name"></a> [function\_name](#input\_function\_name) | Name of the function to invoke. | `string` | n/a | yes |
| <a name="input_qualifier"></a> [qualifier](#input\_qualifier) | Alias or version to invoke. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the function. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->