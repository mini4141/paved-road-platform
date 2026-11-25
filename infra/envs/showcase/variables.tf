variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "aws_profile" {
  type    = string
  default = "paved-road-platform-deployer"
}

variable "cluster_name" {
  type    = string
  default = "paved-road"
}

variable "kubernetes_version" {
  description = "Latest EKS version supported at deploy time (see docs/DECISIONS.md)."
  type        = string
  default     = "1.37"
}
