variable "create" {
  description = "Conditionally create"
  type        = bool
}

variable "name" {
  description = "Name of the service"
  type        = string
}

variable "scan_on_push" {
  description = "Scan images for vulnerabilities"
  type        = string
}