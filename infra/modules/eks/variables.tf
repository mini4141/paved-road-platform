variable "name" {
  description = "Cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets for the control plane ENIs and the node group."
  type        = list(string)
}

variable "instance_types" {
  description = "Node group instance types (SPOT)."
  type        = list(string)
  default     = ["t3.large"]
}
