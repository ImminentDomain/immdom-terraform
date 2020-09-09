variable "aws_region" {
  description = "The AWS region to run the module in"
  type        = string
  default     = "us-east-2"
}

variable "name" {
  description = "The AWS region to run the module in"
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map
  default     = {}
}

variable "enable_billing_alert" {
  description = "Enable billing Cloudwatch alert"
  type        = bool
  default     = true
}

variable "billing_alert_threshold" {
  description = "Set threshold in USD to alert on"
  type        = number
  default     = 300
}

variable "cidr" {
  description = "The CIDR range of the VPC being created"
  type        = string
  default     = "10.0.0.0/16"
}

# Needs a VPN or Bastion host to really use, but the rest is ready to go.
variable "private_networking" {
  description = "Enable private networking in the VPC"
  type        = bool
  default     = false
}

variable "num_azs" {
  description = "The number of availability zones to use"
  type        = number
  default     = 2
}

variable "allowed_public_cidrs" {
  description = "The external public CIDRs to set ingress rules for to access resources"
  type        = list
  default     = []
}

variable "eks_node_type" {
  description = "The AWS region to run the module in"
  type        = string
  default     = "t3.small"
}

variable "eks_max_nodes" {
  description = "The AWS region to run the module in"
  type        = number
  default     = 3
}

variable "services" {
  description = "List of service definitions to run"
  type        = map
  default     = {}
}
