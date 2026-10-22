# Partial configuration, completed at init time (see infra/envs/<env>/backend.hcl):
#   tofu -chdir=infra/stacks/platform init \
#     -backend-config=../../envs/<env>/backend.hcl -backend-config="key=<env>/platform.tfstate"
terraform {
  backend "s3" {}
}
