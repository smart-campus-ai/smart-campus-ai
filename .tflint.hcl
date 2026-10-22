# Run through `task lint:tf` (tflint --init, then tflint --recursive).
# deep_check is left off on purpose: it needs AWS credentials and must never run locally or in the PR plan role.

config {
  # Local modules only; remote modules would require `tflint --init` to download them.
  call_module_type = "local"
}

# Bundled ruleset; the version is the tflint binary pinned in .mise.toml.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
