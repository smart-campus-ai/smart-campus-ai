# SLA escalation (RF01, ADR-0008): schedule group, scheduler execution role limited to the escalation alias, and the DLQ
# of the schedule targets. The schedules themselves are created at runtime by the tickets function.
module "sla_scheduler" {
  source = "../../modules/sla-scheduler"

  name_prefix              = var.name_prefix
  escalation_alias_arn     = module.escalation.alias_arn
  permissions_boundary_arn = local.permissions_boundary_arn
  dlq_kms_key_arn          = local.kms_key_arns["data"]
}
