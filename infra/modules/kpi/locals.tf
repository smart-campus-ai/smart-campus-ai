locals {
  name     = "${var.name_prefix}-kpi"
  dlq_name = "${local.name}-aggregator-dlq"

  # Event filter (OR of the two patterns below). Only the ticket item (sort key META) matters:
  # the EVENT#<ts> audit items and TTL/other removals never wake up the aggregator.
  #   - creation: INSERT of the ticket item;
  #   - status change candidates: MODIFY of the ticket item where both images carry a status.
  #
  # LIMITATION (AC2): DynamoDB stream filters cannot express "OldImage.status != NewImage.status".
  # The MODIFY pattern only verifies that both images have a status attribute. The handler must:
  #   1. Compare old and new status values and ignore MODIFY records where status did not change.
  #   2. Deduplicate by sequence number (replay safety).
  # This contract is documented in the README for SE implementation.
  ticket_keys = {
    (var.ticket_sort_key_name) = { S = [var.ticket_meta_sort_key_value] }
  }

  creation_pattern = jsonencode({
    eventName = ["INSERT"]
    dynamodb = {
      Keys = local.ticket_keys
    }
  })

  status_change_pattern = jsonencode({
    eventName = ["MODIFY"]
    dynamodb = {
      Keys     = local.ticket_keys
      OldImage = { (var.ticket_status_attribute_name) = { S = [{ exists = true }] } }
      NewImage = { (var.ticket_status_attribute_name) = { S = [{ exists = true }] } }
    }
  })
}
