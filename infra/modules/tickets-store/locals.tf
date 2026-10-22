locals {
  name = "${var.name_prefix}-tickets"

  # GSI names. The status index also serves the SLA and KPI reads (by status, newest first).
  owner_index_name  = "by-owner"
  status_index_name = "by-status"

  # Attribute definitions: only key attributes (table and indexes) are declared, all strings.
  key_attributes = toset([
    var.partition_key_name,
    var.sort_key_name,
    var.owner_attribute_name,
    var.status_attribute_name,
    var.created_at_attribute_name,
  ])

  # Contributor Insights targets: the table (null index) and each index.
  insights_targets = var.enable_contributor_insights ? {
    table                     = null
    (local.owner_index_name)  = local.owner_index_name
    (local.status_index_name) = local.status_index_name
  } : {}
}
