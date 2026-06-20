# ─── ARTIFACTS BUCKET ──────────────────────────────────────────────────
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.app_name}-pipeline-artifacts-362857715742"
  force_destroy = true

  tags = {
    Name = "${var.app_name}-pipeline-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── SNS TOPIC (manual approval emails) ────────────────────────────────
resource "aws_sns_topic" "pipeline_approval" {
  name = "${var.app_name}-pipeline-approval"
}

resource "aws_sns_topic_subscription" "pipeline_approval_email" {
  topic_arn = aws_sns_topic.pipeline_approval.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

# ─── GITHUB CONNECTION ─────────────────────────────────────────────────
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.app_name}-github"
  provider_type = "GitHub"
}

# ─── CODEBUILD PROJECT ─────────────────────────────────────────────────
resource "aws_codebuild_project" "app" {
  name          = "${var.app_name}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "APP_NAME"
      value = var.app_name
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = "myapp-tf-state-362857715742"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  vpc_config {
    vpc_id             = aws_vpc.main.id
    subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.app.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${var.app_name}"
      stream_name = "build-log"
    }
  }
}

# ─── CODEPIPELINE ──────────────────────────────────────────────────────
resource "aws_codepipeline" "app" {
  name     = "${var.app_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # STAGE 1: Pull source from GitHub
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  # STAGE 2: Build and test
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  # STAGE 3: Manual approval before applying
  stage {
    name = "Approve"
    action {
      name     = "ApproveDeployment"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.pipeline_approval.arn
        CustomData      = "Please review the Terraform plan and approve to deploy."
      }
    }
  }

  # STAGE 4: Terraform apply via CodeBuild
  stage {
    name = "Deploy"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ProjectName          = aws_codebuild_project.app.name
        EnvironmentVariables = jsonencode([{
          name  = "ACTION"
          value = "apply"
          type  = "PLAINTEXT"
        }])
      }
    }
  }
}

# ─── OUTPUTS ───────────────────────────────────────────────────────────
output "pipeline_url" {
  value = "https://eu-west-2.console.aws.amazon.com/codesuite/codepipeline/pipelines/${var.app_name}-pipeline/view"
}

output "github_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "artifacts_bucket" {
  value = aws_s3_bucket.pipeline_artifacts.bucket
}
