# -----------------------------------------------------------------------------
# Container registry for the RAG app image (llm-load-testing-demo).
#
# Lives in the infra stack because it must exist BEFORE the image is built and
# pushed (`make build-rag`), and before the workload stack deploys it.
# EKS nodes can already pull from it: the node role has
# AmazonEC2ContainerRegistryReadOnly (added by the EKS module).
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "rag_app" {
  name = "${var.project}/rag-app"

  # Demo repo: let `terraform destroy` delete it even when it still has images.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# Keep the registry small: only the 5 newest images survive.
resource "aws_ecr_lifecycle_policy" "rag_app" {
  repository = aws_ecr_repository.rag_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

output "rag_app_repository_url" {
  value = aws_ecr_repository.rag_app.repository_url
}
