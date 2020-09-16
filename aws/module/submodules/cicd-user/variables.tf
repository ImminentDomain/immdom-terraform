variable "create" {
  description = "Conditionally create"
  type        = bool
}

variable "name" {
  description = "Name of the service"
  type        = string
}

variable "ecr_repository" {
  description = "Name of the ecr repository arn"
  type        = string
}

variable "ecr_repository_url" {
  description = "Name of the ecr repository url"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the eks cluster"
  type        = string
}

variable "eks_cluster_arn" {
  description = "Name of the eks cluster arn"
  type        = string
}

variable "tags" {
  description = "Map of tags"
}

variable "aws_region" {
  description = "Name of the aws region"
  type        = string
}
