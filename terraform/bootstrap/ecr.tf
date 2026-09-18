resource "aws_ecr_repository" "training_image" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "training_image" {
  repository = aws_ecr_repository.training_image.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        # GPU images are ~4-5 GB each and tagged images never age out
        # on their own; keep only the two most recent.
        rulePriority = 2
        description  = "Keep only the 2 most recent gpu-* images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["gpu-"]
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Keep at most 10 images overall"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
