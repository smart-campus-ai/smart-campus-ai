# Policies the platform stack attaches to the roles of the functions that use the knowledge base (EN-51 AC5). They are
# exposed as JSON so that each function keeps its own role (one role per function).

# chat: query the knowledge base and generate the answer with the configured inference profile.
data "aws_iam_policy_document" "retrieve" {
  statement {
    sid       = "RetrieveFromKnowledgeBase"
    effect    = "Allow"
    actions   = ["bedrock:Retrieve"]
    resources = [aws_bedrockagent_knowledge_base.this.arn]
  }

  # A cross-region profile is authorized on the profile itself and on the foundation model of every region it routes to.
  statement {
    sid       = "InvokeInferenceProfile"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = distinct(concat([var.inference_profile_arn], var.inference_model_arns))
  }
}

# kb-sync: start and follow ingestion jobs. IAM has no resource type for a data source, so the knowledge base is the
# narrowest scope; the module has a single data source.
data "aws_iam_policy_document" "sync" {
  statement {
    sid    = "IngestKnowledgeBaseDocuments"
    effect = "Allow"
    actions = [
      "bedrock:GetIngestionJob",
      "bedrock:StartIngestionJob",
    ]
    resources = [aws_bedrockagent_knowledge_base.this.arn]
  }
}
