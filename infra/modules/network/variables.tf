variable "name" {
  description = "Name prefix; also the EKS cluster name used in subnet tags."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (one public subnet each)."
  type        = number
  default     = 2
}
