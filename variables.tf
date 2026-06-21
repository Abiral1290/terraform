variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-2"
}

variable "github_repo" {
  description = "GitHub repo in format owner/repo-name"
  type        = string
  default     = "Abiral1290/terraform"
}

variable "github_branch" {
  description = "Branch to trigger the pipeline"
  type        = string
  default     = "main"
}

variable "approval_email" {
  description = "Email address to receive approval notifications"
  type        = string
  default     = "ambubhandarisa16@gmail.com"
}
