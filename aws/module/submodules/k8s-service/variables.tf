variable "name" {
  description = "Name of the service"
  type        = string
}

variable "db_host" {
  description = "Name of the db host"
  type        = string
}

variable "db_name" {
  description = "Name of the db name"
  type        = string
}

variable "db_user" {
  description = "Name of the db user"
  type        = string
}

variable "db_pass" {
  description = "Name of the db pass"
  type        = string
}

variable "db_port" {
  description = "Name of the db port"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the s3 bucket"
  type        = string
}

variable "s3_bucket_arn" {
  description = "Name of the s3 bucket arn"
  type        = string
}

variable "account_id" {
  description = "Name of the aws account id"
  type        = string
}

variable "replicas" {
  description = "Name of the replicas"
  type        = number
}

variable "ecr_repository" {
  description = "Name of the ecr repository"
  type        = string
}

variable "container_port" {
  description = "Name of the container port"
  type        = number
}

variable "create" {
  description = "Conditionally create"
  type        = bool
}
