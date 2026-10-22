# Partial configuration, completed at init time (see infra/envs/<env>/backend.hcl):
#   tofu -chdir=infra/stacks/foundation init \
#     -backend-config=../../envs/<env>/backend.hcl -backend-config="key=<env>/foundation.tfstate"
terraform {
  backend "s3" {}
}
